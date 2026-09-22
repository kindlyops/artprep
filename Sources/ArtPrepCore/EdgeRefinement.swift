import CoreGraphics
import Foundation

public enum EdgeRefinement {
    public static func refine(_ points: [Vertex], image: CGImage) throws -> [Vertex] {
        let size = ImageSize(width: image.width, height: image.height)
        try Outline.validate(points, in: size)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let data = context.data
        else { throw ArtPrepError("Not enough memory to refine this photo.") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let sampler = PixelSampler(data: data.assumingMemoryBound(to: UInt8.self), size: size)
        var perimeter = 0.0
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            perimeter += hypot(b.x - a.x, b.y - a.y)
        }
        let spacing = max(16, perimeter / 800)
        var result: [Vertex] = []
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            result.append(a)
            result.append(contentsOf: refineSegment(a, b, spacing: spacing, sampler: sampler))
        }
        try Outline.validate(result, in: size)
        return result
    }

    private static func refineSegment(
        _ a: Vertex, _ b: Vertex, spacing: Double,
        sampler: PixelSampler
    ) -> [Vertex] {
        let length = hypot(b.x - a.x, b.y - a.y)
        let count = max(1, Int(length / spacing))
        let normal = Vertex(x: -(b.y - a.y) / length, y: (b.x - a.x) / length)
        return (1..<count).map { step in
            let t = Double(step) / Double(count)
            let point = Vertex(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            return sampler.nearbyEdge(point, normal: normal)
        }
    }
}

private struct PixelSampler {
    let data: UnsafePointer<UInt8>
    let size: ImageSize

    func nearbyEdge(_ point: Vertex, normal: Vertex) -> Vertex {
        var best = point
        var bestScore = 60.0
        for offset in -8...8 {
            let candidate = Vertex(
                x: point.x + normal.x * Double(offset),
                y: point.y + normal.y * Double(offset))
            guard candidate.x >= 0, candidate.y >= 0,
                candidate.x < Double(size.width), candidate.y < Double(size.height)
            else { continue }
            let inside = color(Vertex(x: candidate.x - normal.x * 2, y: candidate.y - normal.y * 2))
            let outside = color(
                Vertex(x: candidate.x + normal.x * 2, y: candidate.y + normal.y * 2))
            let score =
                zip(inside, outside).reduce(0.0) { $0 + abs($1.0 - $1.1) }
                - Double(abs(offset)) * 3
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        return best
    }

    private func color(_ point: Vertex) -> [Double] {
        let x = max(0, min(size.width - 1, Int(point.x.rounded())))
        let y = max(0, min(size.height - 1, Int(point.y.rounded())))
        let index = (y * size.width + x) * 4
        return [Double(data[index]), Double(data[index + 1]), Double(data[index + 2])]
    }
}
