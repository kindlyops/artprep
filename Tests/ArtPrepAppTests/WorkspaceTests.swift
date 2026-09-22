import ArtPrepCore
import XCTest

@testable import ArtPrep

final class WorkspaceTests: XCTestCase {
    @MainActor
    func testBusyAndExportingPreventOutlineChanges() {
        let workspace = Workspace()
        let photo = PhotoRecord(
            source: "/tmp/test.png", size: ImageSize(width: 100, height: 100),
            points: [Vertex(x: 10, y: 10)])
        workspace.photos = [photo]
        workspace.selected = photo.id
        workspace.busy = true
        workspace.edit(points: [], closed: false)
        XCTAssertEqual(workspace.current, photo)
        workspace.removePhoto()
        XCTAssertEqual(workspace.photos, [photo])
        workspace.busy = false
        workspace.exporting = true
        workspace.edit(points: [], closed: false)
        XCTAssertEqual(workspace.current, photo)
    }
}
