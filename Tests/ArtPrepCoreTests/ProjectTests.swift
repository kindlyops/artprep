import Foundation
import XCTest

@testable import ArtPrepCore

final class ProjectTests: XCTestCase {
    func testPartialProjectRetainsOutlineAndSourcePath() throws {
        let photo = PhotoRecord(
            source: "/tmp/Artist's painting 日本.JPG",
            size: ImageSize(width: 800, height: 600),
            points: [Vertex(x: 10, y: 20)], closed: false)
        let project = SavedProject(photos: [photo], settings: ExportSettings())
        let decoded = try SavedProject.decode(JSONEncoder().encode(project))
        XCTAssertEqual(decoded.photos[0].points, [Vertex(x: 10, y: 20)])
        XCTAssertEqual(decoded.photos[0].source, "/tmp/Artist's painting 日本.JPG")
        XCTAssertFalse(decoded.photos[0].closed)
    }

    func testRejectsUnknownVersionAndBadSettings() throws {
        var project = SavedProject(photos: [], settings: ExportSettings())
        project.version = 99
        XCTAssertThrowsError(try SavedProject.decode(JSONEncoder().encode(project)))
        project.version = 1
        project.settings.background = "definitely not a color"
        XCTAssertThrowsError(try SavedProject.decode(JSONEncoder().encode(project)))
    }

    func testRejectsDuplicateIDsAndOutOfRangePartialPoints() throws {
        var photo = PhotoRecord(source: "/tmp/photo.png", size: ImageSize(width: 100, height: 100))
        var project = SavedProject(photos: [photo, photo], settings: ExportSettings())
        XCTAssertThrowsError(try SavedProject.decode(JSONEncoder().encode(project)))
        photo.points = [Vertex(x: 101, y: 50)]
        project.photos = [photo]
        XCTAssertThrowsError(try SavedProject.decode(JSONEncoder().encode(project)))
    }
}
