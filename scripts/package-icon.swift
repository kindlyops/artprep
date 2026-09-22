import Foundation
import ImageIO

// PNG-backed entries used by current macOS application icons. Retina entries
// retain their logical size; macOS derives smaller non-Retina representations.
let entries = [
    ("ic11", "icon_16x16@2x.png", 32),
    ("ic12", "icon_32x32@2x.png", 64),
    ("ic07", "icon_128x128.png", 128),
    ("ic13", "icon_128x128@2x.png", 256),
    ("ic08", "icon_256x256.png", 256),
    ("ic14", "icon_256x256@2x.png", 512),
    ("ic09", "icon_512x512.png", 512),
    ("ic10", "icon_512x512@2x.png", 1024),
]

func element(type: String, payload: Data) throws -> Data {
    guard payload.count <= Int(Int32.max) - 8 else {
        throw NSError(
            domain: "ArtPrepIcon", code: 3,
            userInfo: [
                NSLocalizedDescriptionKey: "The icon representation exceeds the ICNS size limit."
            ])
    }
    var data = Data(type.utf8)
    var length = UInt32(payload.count + 8).bigEndian
    withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
    data.append(payload)
    return data
}

func packageIcon(source: URL, output: URL) throws {
    var contents = Data()
    for (type, filename, size) in entries {
        let payload = try Data(contentsOf: source.appendingPathComponent(filename))
        guard let image = CGImageSourceCreateWithData(payload as CFData, nil),
            let pixels = CGImageSourceCreateImageAtIndex(image, 0, nil),
            pixels.width == size, pixels.height == size
        else {
            throw NSError(
                domain: "ArtPrepIcon", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Invalid icon image: \(filename); expected \(size)×\(size)."
                ])
        }
        contents.append(try element(type: type, payload: payload))
    }
    let icon = try element(type: "icns", payload: contents)
    guard let decoded = CGImageSourceCreateWithData(icon as CFData, nil),
        CGImageSourceGetCount(decoded) == entries.count
    else {
        throw NSError(
            domain: "ArtPrepIcon", code: 2,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "macOS could not decode the packaged icon representations."
            ])
    }
    try icon.write(to: output, options: .atomic)
}

let arguments = CommandLine.arguments
if arguments.count != 3 {
    FileHandle.standardError.write(
        Data("Usage: package-icon.swift input.iconset output.icns\n".utf8))
    exit(2)
}
do {
    try packageIcon(
        source: URL(fileURLWithPath: arguments[1]),
        output: URL(fileURLWithPath: arguments[2]))
} catch {
    FileHandle.standardError.write(
        Data("Icon packaging failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
