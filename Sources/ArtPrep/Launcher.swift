import AppKit
import ArtPrepCore
import SwiftUI

@main
@MainActor
enum Launcher {
    static var rendererURL: URL {
        if let path = ProcessInfo.processInfo.environment["ARTPREP_RENDERER"] {
            return URL(fileURLWithPath: path)
        }
        return (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("renderer")
    }

    static func main() {
        let arguments = CommandLine.arguments
        if arguments.count > 1 {
            runCLI(arguments)
            return
        }
        ArtPrepApp.main()
    }

    private static func runCLI(_ arguments: [String]) {
        guard arguments.count == 5, arguments[1] == "--render", arguments[3] == "--output" else {
            print("Usage: ArtPrep --render project.artprep --output /path/to/folder")
            exit(2)
        }
        do {
            let project = try SavedProject.decode(
                Data(contentsOf: URL(fileURLWithPath: arguments[2])))
            guard let gimp = Renderer.installedGimp() else {
                throw ArtPrepError("Install GIMP 3 first.")
            }
            let renderer = Renderer(executable: gimp, scripts: rendererURL)
            let ready = project.photos.filter(\.closed)
            guard !ready.isEmpty else { throw ArtPrepError("No closed outlines in the project.") }
            for photo in ready {
                let url = try renderer.export(
                    photo: photo, settings: project.settings,
                    to: URL(fileURLWithPath: arguments[4]))
                print(url.path)
            }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}

struct ArtPrepApp: App {
    @StateObject private var workspace = Workspace()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Art Prep") {
            ContentView(workspace: workspace)
                .frame(minWidth: 1000, minHeight: 650)
                .onAppear {
                    delegate.workspace = workspace
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Photos…", action: workspace.addPhotos).keyboardShortcut("o")
                Button("Open Project…", action: workspace.openProject).keyboardShortcut(
                    "o", modifiers: [.command, .shift])
                Button("Save Project…", action: workspace.saveProject).keyboardShortcut("s")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Outline Edit", action: workspace.undo).keyboardShortcut("z")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var workspace: Workspace?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard workspace?.exporting != true else { return .terminateCancel }
        return workspace?.confirmDiscard() == false ? .terminateCancel : .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
