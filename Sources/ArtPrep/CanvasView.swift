import AppKit
import ArtPrepCore
import SwiftUI

struct CanvasView: NSViewRepresentable {
    let image: PhotoImage
    let photo: PhotoRecord
    let settings: ExportSettings
    let preview: Bool
    let zoom: Double
    let enabled: Bool
    let onEdit: ([Vertex], Bool) -> Void

    func makeNSView(context: Context) -> CanvasScroll {
        let scroll = CanvasScroll()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = OutlineView()
        scroll.drawsBackground = true
        scroll.backgroundColor = .windowBackgroundColor
        return scroll
    }

    func updateNSView(_ scroll: CanvasScroll, context: Context) {
        guard let view = scroll.documentView as? OutlineView else { return }
        view.image = image.image
        view.size = photo.size
        view.points = photo.points
        view.closed = photo.closed
        view.preview = preview
        view.settings = settings
        view.zoom = zoom
        view.enabled = enabled
        view.onEdit = onEdit
        view.updateSize(viewport: scroll.contentSize)
    }
}

final class CanvasScroll: NSScrollView {
    override func layout() {
        super.layout()
        (documentView as? OutlineView)?.updateSize(viewport: contentSize)
    }
}

final class OutlineView: NSView {
    var image: CGImage?
    var size = ImageSize(width: 1, height: 1)
    var points: [Vertex] = []
    var closed = false
    var preview = false
    var settings = ExportSettings()
    var zoom = 1.0
    var enabled = true
    var onEdit: (([Vertex], Bool) -> Void)?
    private var scale = 1.0
    private var origin = Vertex(x: 0, y: 0)
    private var selectedPoint: Int?
    private var moved = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func updateSize(viewport: NSSize) {
        let layout = preview ? try? CanvasLayout.make(points: points, margin: settings.margin) : nil
        let width = Double(layout?.width ?? size.width)
        let height = Double(layout?.height ?? size.height)
        let fit = max(0.001, min((viewport.width - 60) / width, (viewport.height - 60) / height))
        scale = fit * zoom
        let dimensions = NSSize(
            width: max(viewport.width, width * scale + 60),
            height: max(viewport.height, height * scale + 60))
        if frame.size != dimensions { setFrameSize(dimensions) }
        origin = Vertex(
            x: (dimensions.width - width * scale) / 2,
            y: (dimensions.height - height * scale) / 2)
        if let layout {
            origin.x += Double(layout.offsetX) * scale
            origin.y += Double(layout.offsetY) * scale
        }
        needsDisplay = true
    }

    private var mapping: ImageMapping { ImageMapping(image: size, scale: scale, origin: origin) }
    private func viewPoint(_ vertex: Vertex) -> NSPoint {
        let point = mapping.toView(vertex)
        return NSPoint(x: point.x, y: point.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard let image else { return }
        let rectangle = NSRect(
            x: origin.x, y: origin.y,
            width: Double(size.width) * scale, height: Double(size.height) * scale)
        NSGraphicsContext.saveGraphicsState()
        if preview, let layout = try? CanvasLayout.make(points: points, margin: settings.margin) {
            let canvas = NSRect(
                x: origin.x - Double(layout.offsetX) * scale,
                y: origin.y - Double(layout.offsetY) * scale,
                width: Double(layout.width) * scale, height: Double(layout.height) * scale)
            NSColor(hex: settings.background).setFill()
            canvas.fill()
            outlinePath().addClip()
        }
        NSImage(cgImage: image, size: rectangle.size).draw(
            in: rectangle, from: .zero,
            operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        if !preview { drawOutline() }
    }

    private func outlinePath() -> NSBezierPath {
        let path = NSBezierPath()
        if let first = points.first { path.move(to: viewPoint(first)) }
        for point in points.dropFirst() { path.line(to: viewPoint(point)) }
        if closed { path.close() }
        return path
    }

    private func drawOutline() {
        let path = outlinePath()
        NSColor.black.withAlphaComponent(0.65).setStroke()
        path.lineWidth = 3.5
        path.stroke()
        NSColor.systemYellow.setStroke()
        path.lineWidth = 1.5
        path.stroke()
        var previous: NSPoint?
        for (index, point) in points.enumerated() {
            let center = viewPoint(point)
            if let previous, index != selectedPoint,
                hypot(center.x - previous.x, center.y - previous.y) < 14
            {
                continue
            }
            previous = center
            let dot = NSBezierPath(
                ovalIn: NSRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
            (index == selectedPoint ? NSColor.systemOrange : NSColor.white).setFill()
            dot.fill()
            NSColor.black.setStroke()
            dot.lineWidth = 1
            dot.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard enabled, !preview else { return }
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        guard let point = mapping.toImage(Vertex(x: location.x, y: location.y)) else { return }
        if event.clickCount == 2, points.count >= 3 {
            onEdit?(points, true)
            return
        }
        selectedPoint = points.indices.min {
            distance(points[$0], location) < distance(points[$1], location)
        }
        if let index = selectedPoint, distance(points[index], location) < 10 { return }
        selectedPoint = nil
        if closed {
            insertOnEdge(point, at: location)
        } else {
            points.append(point)
            selectedPoint = points.count - 1
            moved = true
        }
        needsDisplay = true
    }

    private func distance(_ point: Vertex, _ location: NSPoint) -> Double {
        let view = viewPoint(point)
        return hypot(view.x - location.x, view.y - location.y)
    }

    private func insertOnEdge(_ point: Vertex, at location: NSPoint) {
        for index in points.indices {
            let a = viewPoint(points[index])
            let b = viewPoint(points[(index + 1) % points.count])
            let dx = b.x - a.x
            let dy = b.y - a.y
            let denominator = dx * dx + dy * dy
            guard denominator > 0 else { continue }
            let t = max(
                0, min(1, ((location.x - a.x) * dx + (location.y - a.y) * dy) / denominator))
            if hypot(location.x - a.x - t * dx, location.y - a.y - t * dy) < 10 {
                points.insert(point, at: index + 1)
                selectedPoint = index + 1
                moved = true
                return
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard enabled, !preview, let index = selectedPoint, points.indices.contains(index) else {
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        guard let point = mapping.toImage(Vertex(x: location.x, y: location.y)) else { return }
        points[index] = point
        moved = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if moved { onEdit?(points, closed) }
        moved = false
    }

    override func keyDown(with event: NSEvent) {
        if [51, 117].contains(event.keyCode), enabled, !preview,
            let index = selectedPoint, points.indices.contains(index)
        {
            points.remove(at: index)
            selectedPoint = nil
            onEdit?(points, closed && points.count >= 3)
            needsDisplay = true
        } else {
            super.keyDown(with: event)
        }
    }
}

extension NSColor {
    convenience init(hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0xF3EFE7
        self.init(
            srgbRed: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
    }
    var hex: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(
            format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}
