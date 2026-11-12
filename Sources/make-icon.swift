import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1).setFill()
    rect.fill()
    guard let symbol = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: "apple") else { return false }
    let config = NSImage.SymbolConfiguration(pointSize: 620, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let mark = symbol.withSymbolConfiguration(config) ?? symbol
    let box = NSRect(x: 180, y: 150, width: 664, height: 740)
    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.setShadow(offset: .zero, blur: 56, color: NSColor(white: 1, alpha: 0.9).cgColor)
    }
    mark.draw(in: box)
    mark.draw(in: box)
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("could not render icon\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote")
