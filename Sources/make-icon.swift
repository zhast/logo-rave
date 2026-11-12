import AppKit

@main
struct IconGenerator {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "LogoRave.Icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected output PNG path"])
        }
        guard let mark = SymbolStyle.image("apple.logo", pointSize: 620, color: .white) else {
            throw NSError(domain: "LogoRave.Icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "apple.logo symbol unavailable"])
        }
        // SF Symbols carry alignment padding. Center the visible silhouette,
        // not its nominal image canvas (which can be asymmetric).
        let raster = NSImage(size: mark.size, flipped: false) { rect in
            mark.draw(in: rect)
            return true
        }
        guard let cg = raster.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "LogoRave.Icon", code: 4)
        }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { throw NSError(domain: "LogoRave.Icon", code: 5) }
        let visible = NSRect(x: Double(minX), y: Double(bitmap.pixelsHigh - maxY - 1),
                             width: Double(maxX - minX + 1), height: Double(maxY - minY + 1))
        let fit = SymbolStyle.aspectFit(visible.size, in: NSRect(x: 290, y: 240, width: 444, height: 544))
        let scale = fit.width / visible.width
        let box = NSRect(x: fit.minX - visible.minX * scale, y: fit.minY - visible.minY * scale,
                         width: Double(bitmap.pixelsWide) * scale, height: Double(bitmap.pixelsHigh) * scale)
        let centeredMark = NSImage(cgImage: cg, size: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        let image = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { rect in
            NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 96, dy: 96), xRadius: 180, yRadius: 180).fill()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 38, color: NSColor(white: 1, alpha: 0.65).cgColor)
            centeredMark.draw(in: box)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "LogoRave.Icon", code: 3)
        }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
