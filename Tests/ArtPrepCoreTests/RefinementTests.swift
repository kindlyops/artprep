import CoreGraphics
import XCTest

@testable import ArtPrepCore

final class RefinementTests: XCTestCase {
    func testRefinementUsesTopOriginRowsForAsymmetricArtwork() throws {
        var pixels = [UInt8](repeating: 255, count: 200 * 200 * 4)
        for y in 30..<100 {
            for x in 40..<160 {
                for channel in 0..<3 { pixels[(y * 200 + x) * 4 + channel] = 0 }
            }
        }
        let data = Data(pixels) as CFData
        let provider = try XCTUnwrap(CGDataProvider(data: data))
        let image = try XCTUnwrap(
            CGImage(
                width: 200, height: 200, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: 800, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let points = [
            Vertex(x: 37, y: 27), Vertex(x: 163, y: 27),
            Vertex(x: 163, y: 103), Vertex(x: 37, y: 103),
        ]
        let refined = try EdgeRefinement.refine(points, image: image)
        let top = refined.filter { $0.x > 60 && $0.x < 140 && $0.y < 50 }
        XCTAssertFalse(top.isEmpty)
        XCTAssertTrue(top.allSatisfy { abs($0.y - 30) <= 2 })
    }

    func testRefinementFindsNearbyEdgeWithoutMovingCorners() throws {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 200, height: 200,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 40, y: 40, width: 120, height: 120))
        let image = try XCTUnwrap(context.makeImage())
        let points = [
            Vertex(x: 37, y: 37), Vertex(x: 163, y: 37),
            Vertex(x: 163, y: 163), Vertex(x: 37, y: 163),
        ]
        let refined = try EdgeRefinement.refine(points, image: image)
        XCTAssertTrue(refined.contains(points[0]))
        let top = refined.filter { $0.x > 60 && $0.x < 140 && $0.y < 60 }
        XCTAssertFalse(top.isEmpty)
        XCTAssertTrue(top.allSatisfy { abs($0.y - 40) <= 2 })
        try Outline.validate(refined, in: ImageSize(width: 200, height: 200))
    }
}
