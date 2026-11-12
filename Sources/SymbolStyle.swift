import AppKit

/// Shared symbol configuration and geometry for the menu bar, panel and app icon.
enum SymbolStyle {
    static func image(_ name: String, pointSize: CGFloat, description: String? = nil,
                      color: NSColor? = nil) -> NSImage? {
        guard let source = NSImage(systemSymbolName: name, accessibilityDescription: description) else { return nil }
        var configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        if let color {
            configuration = configuration.applying(.init(paletteColors: [color]))
        }
        return source.withSymbolConfiguration(configuration)
    }

    static func aspectFit(_ size: NSSize, in bounds: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }
}


/// Fill and outline share one raster, canvas, and alpha-weighted optical anchor.
/// Scaling about that anchor keeps the heavy body centered despite the separate leaf.
struct LogoArtwork {
    let fill: NSImage
    let outline: NSImage
    let anchor: NSPoint

    func rect(center: NSPoint, scale: Double) -> NSRect {
        let base = SymbolStyle.aspectFit(fill.size, in: NSRect(x: 0, y: 0, width: 60, height: 72))
        let size = NSSize(width: base.width * scale, height: base.height * scale)
        return NSRect(x: center.x - anchor.x * size.width,
                      y: center.y - anchor.y * size.height,
                      width: size.width, height: size.height)
    }

    static func make() -> LogoArtwork? {
        guard let symbol = SymbolStyle.image("apple.logo", pointSize: 96, color: .white) else { return nil }
        let size = NSSize(width: symbol.size.width * 4, height: symbol.size.height * 4)
        let canvas = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            return true
        }
        guard let cg = canvas.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let fill = NSImage(cgImage: cg, size: size)
        let bitmap = NSBitmapImageRep(cgImage: cg)
        var weight = 0.0
        var xSum = 0.0
        var ySum = 0.0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                weight += alpha
                xSum += (Double(x) + 0.5) * alpha
                ySum += (Double(y) + 0.5) * alpha
            }
        }
        guard weight > 0 else { return nil }
        let anchor = NSPoint(x: xSum / weight / Double(bitmap.pixelsWide),
                             y: ySum / weight / Double(bitmap.pixelsHigh))
        let contour = NSImage(size: size, flipped: false) { rect in
            for step in 0..<16 {
                let angle = Double(step) * .pi / 8
                fill.draw(in: rect.offsetBy(dx: cos(angle) * 2, dy: sin(angle) * 2),
                          from: .zero, operation: .sourceOver, fraction: 1)
            }
            fill.draw(in: rect, from: .zero, operation: .destinationOut, fraction: 1)
            return true
        }
        guard let outlineCG = contour.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return LogoArtwork(fill: fill, outline: NSImage(cgImage: outlineCG, size: size), anchor: anchor)
    }
}
