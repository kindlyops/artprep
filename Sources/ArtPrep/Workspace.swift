import AppKit
import ArtPrepCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class Workspace: ObservableObject {
    @Published var photos: [PhotoRecord] = []
    @Published var selected: UUID?
    @Published var settings = ExportSettings()
    @Published var image: PhotoImage?
    @Published var preview = false
    @Published var zoom = 1.0
    @Published var message = "Add a photo to begin. Your originals stay untouched."
    @Published var error: String?
    @Published var busy = false
    @Published var exporting = false
    @Published var stopRequested = false
    @Published var statuses: [UUID: String] = [:]
    @Published var outputFolder: URL?
    @Published var dirty = false
    private var history: [UUID: [PhotoRecord]] = [:]
    private var projectURL: URL?
    private var loadTask: Task<Void, Never>?

    var current: PhotoRecord? { photos.first { $0.id == selected } }
    var ready: [PhotoRecord] { photos.filter(\.closed) }

    func addPhotos() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        busy = true
        Task {
            for url in urls where !photos.contains(where: { $0.source == url.path }) {
                do {
                    let loaded = try await Task.detached { try PhotoImage.load(url) }.value
                    let photo = PhotoRecord(source: url.path, size: loaded.size)
                    photos.append(photo)
                    if selected == nil { selected = photo.id }
                    dirty = true
                } catch { self.error = error.localizedDescription }
            }
            busy = false
            selectPhoto()
        }
    }

    func selectPhoto() {
        loadTask?.cancel()
        image = nil
        preview = false
        zoom = 1
        guard let photo = current else { return }
        message = "Mark the outside of the wood. Double-click the last point to close."
        loadTask = Task {
            do {
                let loaded = try await Task.detached {
                    try PhotoImage.load(URL(fileURLWithPath: photo.source))
                }.value
                guard !Task.isCancelled, selected == photo.id else { return }
                guard loaded.size == photo.size else {
                    throw ArtPrepError(
                        "This photo changed size. Remove it and add the current file.")
                }
                image = loaded
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    func edit(points: [Vertex], closed: Bool) {
        guard let index = photos.firstIndex(where: { $0.id == selected }) else { return }
        let before = photos[index]
        guard before.points != points || before.closed != closed else { return }
        if closed {
            do { try Outline.validate(points, in: before.size) } catch {
                self.error = error.localizedDescription
                return
            }
        }
        history[before.id, default: []].append(before)
        if history[before.id, default: []].count > 100 { history[before.id]?.removeFirst() }
        photos[index].points = points
        photos[index].closed = closed
        statuses[before.id] = nil
        dirty = true
    }

    func refine() {
        guard let photo = current, photo.closed, let image else { return }
        busy = true
        Task {
            do {
                let points = try await Task.detached {
                    try EdgeRefinement.refine(photo.points, image: image.image)
                }.value
                if selected == photo.id { edit(points: points, closed: true) }
                message =
                    "Refined nearby edges within 8 photo pixels. Review the result; Undo restores your outline."
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }

    func undo() {
        guard let id = selected, let previous = history[id]?.popLast(),
            let index = photos.firstIndex(where: { $0.id == id })
        else { return }
        photos[index] = previous
        statuses[id] = nil
        dirty = true
    }

    func removePhoto() {
        guard let id = selected else { return }
        photos.removeAll { $0.id == id }
        history[id] = nil
        selected = photos.first?.id
        dirty = true
        selectPhoto()
    }

    func saveProject() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = projectURL?.lastPathComponent ?? "Paintings.artprep"
        panel.allowedContentTypes = [UTType(filenameExtension: "artprep") ?? .json]
        guard panel.runModal() == .OK, var url = panel.url else { return }
        if url.pathExtension != "artprep" { url.appendPathExtension("artprep") }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(SavedProject(photos: photos, settings: settings)).write(
                to: url, options: .atomic)
            projectURL = url
            dirty = false
            message = "Saved \(url.lastPathComponent)."
        } catch { self.error = error.localizedDescription }
    }

    func openProject() {
        guard confirmDiscard() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "artprep") ?? .json, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let project = try SavedProject.decode(Data(contentsOf: url))
            photos = project.photos
            settings = project.settings
            history = [:]
            statuses = [:]
            projectURL = url
            selected = photos.first?.id
            dirty = false
            selectPhoto()
        } catch { self.error = error.localizedDescription }
    }

    func confirmDiscard() -> Bool {
        guard dirty else { return true }
        let alert = NSAlert()
        alert.messageText = "You have unsaved outlines."
        alert.informativeText = "Cancel to save your project, or continue without saving."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Continue without saving")
        return alert.runModal() == .alertSecondButtonReturn
    }

    func chooseOutput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Use this folder"
        guard panel.runModal() == .OK else { return }
        outputFolder = panel.url
    }

    func exportReady() {
        guard let gimp = Renderer.installedGimp() else {
            error = "Install GIMP 3 in Applications, then try Export again."
            return
        }
        if outputFolder == nil { chooseOutput() }
        guard let outputFolder else { return }
        let jobs = ready
        guard !jobs.isEmpty else { return }
        let configuration = settings
        let renderer = Renderer(executable: gimp, scripts: Launcher.rendererURL)
        exporting = true
        stopRequested = false
        Task {
            var completed = 0
            for (index, photo) in jobs.enumerated() {
                if stopRequested { break }
                message = "Exporting \(index + 1) of \(jobs.count): \(photo.name)…"
                statuses[photo.id] = "Exporting…"
                do {
                    let url = try await Task.detached {
                        try renderer.export(photo: photo, settings: configuration, to: outputFolder)
                    }.value
                    statuses[photo.id] = "Exported · \(url.lastPathComponent)"
                    completed += 1
                } catch {
                    statuses[photo.id] = "Failed — ready to retry"
                    self.error = "\(photo.name): \(error.localizedDescription)"
                }
            }
            message =
                "Exported \(completed) of \(jobs.count). Files are in \(outputFolder.lastPathComponent)."
            exporting = false
        }
    }
}
