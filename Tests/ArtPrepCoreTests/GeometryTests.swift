import XCTest

@testable import ArtPrepCore

final class GeometryTests: XCTestCase {
    let size = ImageSize(width: 1000, height: 800)
    let rectangle = [
        Vertex(x: 100, y: 100), Vertex(x: 900, y: 100),
        Vertex(x: 900, y: 700), Vertex(x: 100, y: 700),
    ]

    func testAcceptsEitherWindingAndConcaveFrames() throws {
        XCTAssertNoThrow(try Outline.validate(rectangle, in: size))
        XCTAssertNoThrow(try Outline.validate(Array(rectangle.reversed()), in: size))
        let notched = [
            Vertex(x: 10, y: 10), Vertex(x: 990, y: 10),
            Vertex(x: 990, y: 300), Vertex(x: 700, y: 300),
            Vertex(x: 700, y: 700), Vertex(x: 10, y: 700),
        ]
        XCTAssertNoThrow(try Outline.validate(notched, in: size))
    }

    func testRejectsCrossingsDuplicatesAndInvalidCoordinates() {
        XCTAssertThrowsError(
            try Outline.validate(
                [
                    rectangle[0], rectangle[2],
                    rectangle[1], rectangle[3],
                ], in: size))
        XCTAssertThrowsError(
            try Outline.validate([rectangle[0], rectangle[0], rectangle[2]], in: size))
        XCTAssertThrowsError(
            try Outline.validate([Vertex(x: -.infinity, y: 0)] + rectangle, in: size))
        XCTAssertThrowsError(try Outline.validate([Vertex(x: -1, y: 50)] + rectangle, in: size))
        XCTAssertThrowsError(
            try Outline.validate(
                [
                    Vertex(x: 2, y: 2), Vertex(x: 4, y: 4),
                    Vertex(x: 6, y: 6),
                ], in: size))
        XCTAssertThrowsError(try Outline.validate([], in: size))
    }

    func testCanvasIncludesAllArtworkAndCentersIt() throws {
        let layout = try CanvasLayout.make(points: rectangle, margin: 0.1)
        XCTAssertEqual(layout.width, 1125)
        XCTAssertEqual(layout.height, 750)
        XCTAssertEqual(layout.offsetX, 63)
        XCTAssertEqual(layout.offsetY, -25)
        XCTAssertEqual(layout.socialSize, ImageSize(width: 2000, height: 1333))
    }

    func testPortraitAndInvalidMargins() throws {
        let points = [
            Vertex(x: 10, y: 20), Vertex(x: 310, y: 20),
            Vertex(x: 310, y: 620), Vertex(x: 10, y: 620),
        ]
        let layout = try CanvasLayout.make(points: points, margin: 0.1)
        XCTAssertEqual(layout.width, 600)
        XCTAssertEqual(layout.height, 750)
        XCTAssertEqual(layout.socialSize, ImageSize(width: 1600, height: 2000))
        XCTAssertThrowsError(try CanvasLayout.make(points: points, margin: 0.5))
        XCTAssertThrowsError(try CanvasLayout.make(points: [], margin: 0.1))
    }

    func testZoomedPreviewCoordinatesRoundTripAndRejectOutside() {
        let map = ImageMapping(image: size, scale: 0.5, origin: Vertex(x: 30, y: 70))
        XCTAssertEqual(map.toImage(Vertex(x: 280, y: 270)), Vertex(x: 500, y: 400))
        XCTAssertEqual(map.toView(Vertex(x: 500, y: 400)), Vertex(x: 280, y: 270))
        XCTAssertNil(map.toImage(Vertex(x: 20, y: 100)))
    }
}
