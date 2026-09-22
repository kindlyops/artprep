import Foundation

public struct Vertex: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct ImageSize: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum Outline {
    public static func validate(_ points: [Vertex], in size: ImageSize) throws {
        guard (3...4000).contains(points.count) else {
            throw ArtPrepError("Mark at least three points around the artwork (maximum 4,000).")
        }
        guard size.width > 0, size.height > 0 else {
            throw ArtPrepError("Invalid image dimensions.")
        }
        for point in points {
            guard point.x.isFinite, point.y.isFinite,
                (0...Double(size.width)).contains(point.x),
                (0...Double(size.height)).contains(point.y)
            else {
                throw ArtPrepError(
                    "An outline point is outside the photo. Move it inside the image.")
            }
        }
        try validateEdges(points)
        var area = 0.0
        for i in points.indices {
            let next = points[(i + 1) % points.count]
            area += points[i].x * next.y - next.x * points[i].y
        }
        guard abs(area) > 2 else { throw ArtPrepError("The outline must enclose an area.") }
    }

    private static func validateEdges(_ points: [Vertex]) throws {
        for i in points.indices {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            guard hypot(a.x - b.x, a.y - b.y) > 0.001 else {
                throw ArtPrepError("Two outline points overlap. Delete one or move it.")
            }
            for j in points.indices where j > i + 1 {
                if i == 0 && j == points.count - 1 { continue }
                if intersects(a, b, points[j], points[(j + 1) % points.count]) {
                    throw ArtPrepError("The outline crosses itself. Move the crossing points.")
                }
            }
        }
    }

    private static func cross(_ a: Vertex, _ b: Vertex, _ c: Vertex) -> Double {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    private static func onSegment(_ p: Vertex, _ a: Vertex, _ b: Vertex) -> Bool {
        p.x >= min(a.x, b.x) - 1e-8 && p.x <= max(a.x, b.x) + 1e-8
            && p.y >= min(a.y, b.y) - 1e-8 && p.y <= max(a.y, b.y) + 1e-8
    }

    private static func intersects(_ a: Vertex, _ b: Vertex, _ c: Vertex, _ d: Vertex) -> Bool {
        let abC = cross(a, b, c)
        let abD = cross(a, b, d)
        let cdA = cross(c, d, a)
        let cdB = cross(c, d, b)
        if abC * abD < 0 && cdA * cdB < 0 { return true }
        return (abs(abC) < 1e-8 && onSegment(c, a, b))
            || (abs(abD) < 1e-8 && onSegment(d, a, b))
            || (abs(cdA) < 1e-8 && onSegment(a, c, d))
            || (abs(cdB) < 1e-8 && onSegment(b, c, d))
    }
}

public struct CanvasLayout: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let offsetX: Int
    public let offsetY: Int
    public let socialSize: ImageSize
    public static func make(points: [Vertex], margin: Double) throws -> CanvasLayout {
        guard margin.isFinite, (0...0.3).contains(margin), points.count >= 3,
            points.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
        else {
            throw ArtPrepError("Use a valid outline and margins between 0% and 30%.")
        }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let left = xs.min() ?? 0
        let right = xs.max() ?? 0
        let top = ys.min() ?? 0
        let bottom = ys.max() ?? 0
        let landscape = right - left >= bottom - top
        let ratio = landscape ? 1.5 : 0.8
        let height = ceil(
            max(
                (bottom - top) / (1 - 2 * margin),
                (right - left) / (1 - 2 * margin) / ratio))
        let width = ceil(height * ratio)
        guard width >= 2, height >= 2, width <= 32768, height <= 32768,
            width * height <= 200_000_000
        else {
            throw ArtPrepError(
                "The resulting canvas is too large. Reduce the image size or margins.")
        }
        return CanvasLayout(
            width: Int(width), height: Int(height),
            offsetX: Int((width / 2 - (left + right) / 2).rounded()),
            offsetY: Int((height / 2 - (top + bottom) / 2).rounded()),
            socialSize: landscape
                ? ImageSize(width: 2000, height: 1333)
                : ImageSize(width: 1600, height: 2000)
        )
    }
}

public struct ImageMapping {
    public let image: ImageSize
    public let scale: Double
    public let origin: Vertex
    public init(image: ImageSize, scale: Double, origin: Vertex) {
        self.image = image
        self.scale = scale
        self.origin = origin
    }
    public func toImage(_ point: Vertex) -> Vertex? {
        guard scale > 0, scale.isFinite else { return nil }
        let result = Vertex(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
        guard (0...Double(image.width)).contains(result.x),
            (0...Double(image.height)).contains(result.y)
        else { return nil }
        return result
    }
    public func toView(_ point: Vertex) -> Vertex {
        Vertex(x: point.x * scale + origin.x, y: point.y * scale + origin.y)
    }
}

public struct ArtPrepError: LocalizedError, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
