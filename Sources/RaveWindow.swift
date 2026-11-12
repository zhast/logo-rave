import AppKit
import QuartzCore

final class RavePanel: NSView {
    var level = 0.0
    var beat = false
    var status = "Listening to the room"
    var detail = ""

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1).setFill()
        bounds.fill()

        let title = NSAttributedString(string: "Logo Rave", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor(white: 0.92, alpha: 1),
        ])
        let titleSize = title.size()
        title.draw(at: NSPoint(x: (bounds.width - titleSize.width) / 2, y: 8))

        let lid = NSRect(x: 36, y: 48, width: bounds.width - 72, height: 176)
        let shell = NSBezierPath(roundedRect: lid, xRadius: 22, yRadius: 22)
        NSColor(white: 0.1, alpha: 1).setFill()
        shell.fill()

        NSGraphicsContext.saveGraphicsState()
        shell.addClip()
        drawGlowingLogo(in: lid, level: level)
        NSGraphicsContext.restoreGraphicsState()

        NSColor(white: 1, alpha: 0.08).setStroke()
        shell.lineWidth = 1
        shell.stroke()

        let meter = NSRect(x: 36, y: 244, width: bounds.width - 72, height: 4)
        NSColor(white: 1, alpha: 0.1).setFill()
        NSBezierPath(roundedRect: meter, xRadius: 2, yRadius: 2).fill()
        if level > 0.02 {
            let filled = NSRect(x: meter.minX, y: meter.minY, width: meter.width * level, height: meter.height)
            NSColor(white: 1, alpha: 0.92).setFill()
            NSBezierPath(roundedRect: filled, xRadius: 2, yRadius: 2).fill()
        }
    }

    private func drawGlowingLogo(in lid: NSRect, level: Double) {
        guard let mark = Self.whiteLogo else { return }
        let box = NSRect(x: lid.midX - 30, y: lid.midY - 36, width: 60, height: 72)
        if level > 0.03, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setShadow(
                offset: .zero,
                blur: 3 + 10 * level,
                color: NSColor(white: 1, alpha: min(1, 0.35 + 0.65 * level)).cgColor
            )
            mark.draw(in: box, from: .zero, operation: .sourceOver, fraction: 0.55 + 0.45 * level, respectFlipped: true, hints: nil)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
        }
        mark.draw(in: box, from: .zero, operation: .sourceOver, fraction: 0.22 + 0.78 * level, respectFlipped: true, hints: nil)
    }

    private static let whiteLogo: NSImage? = {
        guard let symbol = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: "logo") else { return nil }
        let canvas = NSImage(size: NSSize(width: 120, height: 144), flipped: false) { rect in
            let config = NSImage.SymbolConfiguration(pointSize: 96, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.white]))
            let mark = symbol.withSymbolConfiguration(config) ?? symbol
            mark.draw(in: rect.insetBy(dx: 8, dy: 10))
            return true
        }
        return canvas
    }()
}

final class RaveApp: NSObject, NSApplicationDelegate {
    var onQuit: (() -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) { onQuit?() }
}

final class RaveWindow: NSObject {
    let panel = RavePanel(frame: NSRect(x: 0, y: 0, width: 280, height: 320))
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let popover = NSPopover()
    let mics = NSPopUpButton(frame: NSRect(x: 16, y: 258, width: 248, height: 26), pullsDown: false)
    let quit = NSButton(title: "Quit", target: nil, action: nil)
    var devices: [(id: UInt32, name: String)] = []
    var onMic: ((UInt32) -> Void)?

    override init() {
        super.init()
        let button = item.button
        let image = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: "Logo Rave")
        image?.isTemplate = true
        button?.image = image
        button?.target = self
        button?.action = #selector(toggle)
        button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        let controller = NSViewController()
        controller.view = panel
        popover.contentViewController = controller
        popover.contentSize = panel.frame.size
        mics.target = self
        mics.action = #selector(pickedMic)
        mics.font = .systemFont(ofSize: 12)
        panel.addSubview(mics)
        quit.target = self
        quit.action = #selector(quitApp)
        quit.isBordered = false
        quit.font = .systemFont(ofSize: 12)
        quit.frame = NSRect(x: 16, y: 290, width: 48, height: 22)
        panel.addSubview(quit)
    }

    func setMics(_ devices: [(id: UInt32, name: String)], selected: UInt32?) {
        self.devices = devices
        mics.removeAllItems()
        if devices.isEmpty {
            mics.addItem(withTitle: "No microphone")
            mics.isEnabled = false
            return
        }
        mics.isEnabled = true
        for device in devices { mics.addItem(withTitle: device.name) }
        if let selected, let index = devices.firstIndex(where: { $0.id == selected }) {
            mics.selectItem(at: index)
        }
    }

    @objc private func pickedMic() {
        let index = mics.indexOfSelectedItem
        guard devices.indices.contains(index) else { return }
        onMic?(devices[index].id)
    }

    @objc private func toggle() {
        guard let button = item.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
            quit.target = self
            menu.addItem(quit)
            item.menu = menu
            button.performClick(nil)
            item.menu = nil
            return
        }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func showPopover() { toggle() }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func show(level: Double) {
        panel.level = level
        panel.needsDisplay = true
        item.button?.alphaValue = 0.35 + 0.65 * level
    }
}

final class DisplayClock: NSObject {
    private var timer: Timer?
    private var last = 0.0
    var onFrame: ((Double) -> Void)?

    func start() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date().timeIntervalSinceReferenceDate
            let dt = self.last == 0 ? 1.0 / 60.0 : min(0.05, max(0.001, now - self.last))
            self.last = now
            self.onFrame?(dt)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
