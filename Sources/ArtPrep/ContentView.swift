import AppKit
import ArtPrepCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar.frame(width: 210)
                Divider()
                editor.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                inspector.frame(width: 235)
            }
            Divider()
            HStack {
                if workspace.exporting || workspace.busy { ProgressView().controlSize(.small) }
                Text(workspace.message).font(.callout).lineLimit(2)
                Spacer()
                if workspace.exporting {
                    Button(
                        workspace.stopRequested
                            ? "Stopping after this photo…" : "Stop after this photo"
                    ) {
                        workspace.stopRequested = true
                    }.disabled(workspace.stopRequested)
                }
            }.padding(12).frame(minHeight: 48)
        }
        .toolbar {
            Button(action: workspace.addPhotos) { Label("Add Photos", systemImage: "plus") }
                .disabled(workspace.locked)
            Button(action: workspace.openProject) { Label("Open Project", systemImage: "folder") }
                .disabled(workspace.locked)
            Button(action: workspace.saveProject) {
                Label("Save Project", systemImage: "square.and.arrow.down")
            }
            .disabled(workspace.photos.isEmpty || workspace.locked)
            Spacer()
            Text("LOCAL · GIMP").font(.caption).foregroundStyle(.secondary)
        }
        .alert(
            "Art Prep",
            isPresented: Binding(
                get: { workspace.error != nil },
                set: { if !$0 { workspace.error = nil } })
        ) {
            Button("OK") { workspace.error = nil }
        } message: {
            Text(workspace.error ?? "")
        }
        .onChange(of: workspace.selected) { _, _ in workspace.selectPhoto() }
        .onChange(of: workspace.settings) { _, _ in workspace.dirty = true }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR PHOTOS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal)
            List(selection: $workspace.selected) {
                ForEach(workspace.photos) { photo in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(photo.name).font(.headline).lineLimit(1)
                        Label(
                            photo.closed ? "Ready to export" : "Mark the outline",
                            systemImage: photo.closed
                                ? "checkmark.circle.fill" : "pencil.tip.crop.circle"
                        )
                        .font(.caption).foregroundStyle(photo.closed ? .green : .secondary)
                        if let status = workspace.statuses[photo.id] {
                            Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }.padding(.vertical, 5).tag(photo.id)
                }
            }.listStyle(.sidebar).disabled(workspace.locked)
            Button("Remove Photo", action: workspace.removePhoto)
                .disabled(workspace.selected == nil || workspace.locked).padding()
        }.padding(.top, 20)
    }

    private var editor: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("View", selection: $workspace.preview) {
                    Text("Outline").tag(false)
                    Text("Cutout Preview").tag(true)
                }.pickerStyle(.segmented).frame(width: 240)
                    .disabled(workspace.current?.closed != true)
                Spacer()
                Text("Zoom").font(.caption)
                Slider(value: $workspace.zoom, in: 0.5...8).frame(width: 110)
                Button("Fit") { workspace.zoom = 1 }
            }.padding(14)
            if let photo = workspace.current, let image = workspace.image {
                CanvasView(
                    image: image, photo: photo, settings: workspace.settings,
                    preview: workspace.preview, zoom: workspace.zoom, enabled: !workspace.locked,
                    onEdit: workspace.edit
                )
                .disabled(workspace.locked)
            } else {
                ContentUnavailableView(
                    "Give your artwork room to shine",
                    systemImage: "photo.artframe",
                    description: Text(
                        "Add a JPEG or PNG, mark the outside of its frame, "
                            + "and export a clean background."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("PREPARE YOUR ART").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("Keep every edge.").font(.title2.weight(.semibold))
            Text("Click around the outside of the wood. Use extra points for staggered boards.")
                .font(.callout).foregroundStyle(.secondary)
            outlineControls
            Divider()
            ColorPicker(
                "Background",
                selection: Binding(
                    get: { Color(nsColor: NSColor(hex: workspace.settings.background)) },
                    set: { workspace.settings.background = NSColor($0).hex }),
                supportsOpacity: false)
            Button("Warm off-white") { workspace.settings.background = "#F3EFE7" }
                .font(.caption)
            VStack(alignment: .leading) {
                Text("Margin · \(Int(workspace.settings.margin * 100))%")
                Slider(value: $workspace.settings.margin, in: 0...0.3, step: 0.01)
            }
            Text(
                "Drag points to adjust. Click an edge to add a point. "
                    + "Select a point and press Delete to remove it."
            )
            .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("Each export includes an editable GIMP file, full-size JPEG, and social JPEG.")
                .font(.caption).foregroundStyle(.secondary)
            Button(
                workspace.outputFolder?.lastPathComponent ?? "Choose Output Folder…",
                action: workspace.chooseOutput
            ).lineLimit(1)
            Button(
                "Export \(workspace.ready.count) Ready "
                    + "Photo\(workspace.ready.count == 1 ? "" : "s")",
                action: workspace.exportReady
            )
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(workspace.ready.isEmpty || workspace.busy)
            if let folder = workspace.outputFolder {
                Button("Show Exports") { NSWorkspace.shared.open(folder) }
            }
        }.padding(20).disabled(workspace.locked)
    }

    private var outlineControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(workspace.current?.closed == true ? "Edit Outline" : "Close Outline") {
                guard let photo = workspace.current else { return }
                if photo.closed {
                    workspace.preview = false
                } else {
                    workspace.edit(points: photo.points, closed: true)
                }
            }.disabled(workspace.current?.points.count ?? 0 < 3)
            Button("Refine Nearby Edges", action: workspace.refine)
                .disabled(workspace.current?.closed != true || workspace.busy)
            HStack {
                Button("Undo", action: workspace.undo)
                Button("Start Over") {
                    workspace.preview = false
                    workspace.edit(points: [], closed: false)
                }
            }.disabled(workspace.current == nil)
        }
    }
}
