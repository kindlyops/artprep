import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import ArtPrepCore

final class ImageTests: XCTestCase {
    func testOrientedInputAndNormalizedOutputHaveSameDimensions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("rotated.jpg")
        let output = directory.appendingPathComponent("normalized.png")
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 80, height: 40,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                input as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let loaded = try PhotoImage.load(input)
        XCTAssertEqual(loaded.size, ImageSize(width: 40, height: 80))
        try PhotoImage.normalize(input, to: output, expected: loaded.size)
        XCTAssertEqual(try PhotoImage.load(output).size, loaded.size)
        XCTAssertThrowsError(
            try PhotoImage.normalize(
                input, to: output,
                expected: ImageSize(width: 80, height: 40)))
    }

    func testMissingAndNonImageFilesGiveActionableErrors() throws {
        XCTAssertThrowsError(try PhotoImage.load(URL(fileURLWithPath: "/no/such/photo.jpg")))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("Not a photo".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try PhotoImage.load(url))
    }
}
