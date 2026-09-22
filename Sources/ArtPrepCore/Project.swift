import Foundation

public struct ExportSettings: Codable, Equatable, Sendable {
    public var background = "#F3EFE7"
    public var margin = 0.08
    public init() {}
}

public struct PhotoRecord: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var source: String
    public var size: ImageSize
    public var points: [Vertex]
    public var closed: Bool
    public init(source: String, size: ImageSize, points: [Vertex] = [], closed: Bool = false) {
        self.source = source
        self.size = size
        self.points = points
        self.closed = closed
    }
    public var name: String {
        URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
    }
}

public struct SavedProject: Codable, Sendable {
    public var version = 1
    public var photos: [PhotoRecord]
    public var settings: ExportSettings
    public init(photos: [PhotoRecord], settings: ExportSettings) {
        self.photos = photos
        self.settings = settings
    }
    public static func decode(_ data: Data) throws -> SavedProject {
        let project = try JSONDecoder().decode(SavedProject.self, from: data)
        guard project.version == 1 else { throw ArtPrepError("Unsupported project version.") }
        try project.settings.validate()
        guard project.photos.count <= 500,
            Set(project.photos.map(\.id)).count == project.photos.count
        else {
            throw ArtPrepError("The project contains duplicate photos or more than 500 photos.")
        }
        for photo in project.photos { try photo.validate() }
        return project
    }
}

extension ExportSettings {
    public func validate() throws {
        guard background.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil,
            margin.isFinite, (0...0.3).contains(margin)
        else {
            throw ArtPrepError("Use a six-digit background color and margins between 0% and 30%.")
        }
    }
}

extension PhotoRecord {
    public func validate() throws {
        guard source.hasPrefix("/"), size.width > 0, size.height > 0,
            size.width <= 32768, size.height <= 32768,
            Int64(size.width) * Int64(size.height) <= 200_000_000
        else {
            throw ArtPrepError("Invalid photo path or dimensions in the project.")
        }
        guard points.count <= 4000,
            points.allSatisfy({ point in
                point.x.isFinite && point.y.isFinite
                    && (0...Double(size.width)).contains(point.x)
                    && (0...Double(size.height)).contains(point.y)
            })
        else { throw ArtPrepError("The project contains an invalid outline point.") }
        if closed { try Outline.validate(points, in: size) }
    }
}
