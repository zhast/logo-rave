import AppKit
import QuartzCore

/// Small value-type animation state, driven by the existing display clock.
struct RippleField {
    struct Ring {
        var age: Double = 0
        let strength: Double
        var progress: Double { min(age / 1.15, 1) }
    }

    private(set) var rings: [Ring] = []
    private var baseline = 0.0
    private var cooldown = 0.0

    mutating func update(level: Double, seconds: Double, active: Bool, reduceMotion: Bool) {
        let dt = min(max(seconds, 0), 0.1)
        guard active && !reduceMotion else {
            rings.removeAll(keepingCapacity: true)
            baseline = level
            cooldown = 0
            return
        }
        for i in rings.indices { rings[i].age += dt }
        rings.removeAll { $0.progress >= 1 }
        cooldown = max(0, cooldown - dt)
        let change = abs(level - baseline)
        if level > 0.04 && change > 0.09 && cooldown == 0 {
            rings.append(Ring(strength: min(1, change * 3)))
            if rings.count > 5 { rings.removeFirst(rings.count - 5) }
            cooldown = 0.18
            baseline = level
        }
        baseline += (level - baseline) * (1 - exp(-dt / 0.25))
    }
}

final class RavePanel: NSView {
    var level = 0.0
    var ripples = RippleField()
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
        drawRipples(in: lid)
        drawGlowingLogo(in: lid, level: level)
        NSGraphicsContext.restoreGraphicsState()

        NSColor(white: 1, alpha: 0.08).setStroke()
        shell.lineWidth = 1
        shell.stroke()

        let statusText = NSAttributedString(string: status, attributes: [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor,
        ])
        statusText.draw(at: NSPoint(x: (bounds.width - statusText.size().width) / 2, y: 228))
        let meter = NSRect(x: 36, y: 244, width: bounds.width - 72, height: 4)
        NSColor(white: 1, alpha: 0.1).setFill()
        NSBezierPath(roundedRect: meter, xRadius: 2, yRadius: 2).fill()
        if level > 0.02 {
            let filled = NSRect(x: meter.minX, y: meter.minY, width: meter.width * level, height: meter.height)
            NSColor(white: 1, alpha: 0.92).setFill()
            NSBezierPath(roundedRect: filled, xRadius: 2, yRadius: 2).fill()
        }
    }

    private func drawRipples(in lid: NSRect) {
        guard let artwork = Self.artwork else { return }
        let contour = artwork.outline
        for ring in ripples.rings {
            let t = ring.progress
            let eased = 1 - pow(1 - t, 2)
            let scale = 1 + eased * 2.1
            let box = artwork.rect(center: NSPoint(x: lid.midX, y: lid.midY), scale: scale)
            let opacity = sin(Double.pi * t) * (1 - t) * (0.18 + 0.28 * ring.strength)
            contour.draw(in: box, from: .zero, operation: .sourceOver,
                         fraction: opacity, respectFlipped: true, hints: nil)
        }
    }

    private func drawGlowingLogo(in lid: NSRect, level: Double) {
        guard let artwork = Self.artwork else { return }
        let mark = artwork.fill
        let box = artwork.rect(center: NSPoint(x: lid.midX, y: lid.midY), scale: 1)
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

    private static let artwork = LogoArtwork.make()

}

final class RaveApp: NSObject, NSApplicationDelegate {
    var onQuit: (() -> Void)?

    // A menu-bar app stays alive when its transient popover/window is dismissed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) { onQuit?() }
}

final class RaveWindow: NSObject {
    let panel = RavePanel(frame: NSRect(x: 0, y: 0, width: 280, height: 290))
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let popover = NSPopover()
    let quit = NSButton(title: "Quit", target: nil, action: nil)
    var onLightEnabled: ((Bool) -> Void)?
    private let lightSwitch = NSButton(checkboxWithTitle: "Light enabled", target: nil, action: nil)

    override init() {
        super.init()
        let button = item.button
        let image = SymbolStyle.image("apple.logo", pointSize: 16, description: "Logo Rave")
        image?.isTemplate = true
        button?.image = image
        button?.imageScaling = .scaleProportionallyDown
        button?.toolTip = "Logo Rave — microphone and light controls"
        button?.target = self
        button?.action = #selector(toggle)
        button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        let controller = NSViewController()
        controller.view = panel
        popover.contentViewController = controller
        popover.contentSize = panel.frame.size
        quit.target = self
        quit.action = #selector(quitApp)
        quit.image = SymbolStyle.image("power", pointSize: 12, description: "Quit")
        quit.imagePosition = .imageLeading
        quit.isBordered = false
        quit.font = .systemFont(ofSize: 12)
        quit.frame = NSRect(x: 16, y: 260, width: 66, height: 22)
        panel.addSubview(quit)
        lightSwitch.frame = NSRect(x: 94, y: 258, width: 170, height: 26)
        lightSwitch.state = .on
        lightSwitch.target = self
        lightSwitch.action = #selector(lightChanged)
        panel.addSubview(lightSwitch)
    }

    @objc private func lightChanged() {
        let enabled = lightSwitch.state == .on
        onLightEnabled?(enabled)
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

    func show(level: Double, seconds: Double = 1.0 / 60.0, animated: Bool = true) {
        panel.level = level
        panel.ripples.update(
            level: level, seconds: seconds, active: popover.isShown && animated,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        // Hidden panels need no redraws; no extra animation timers or layers.
        if popover.isShown { panel.needsDisplay = true }
        item.button?.alphaValue = 0.35 + 0.65 * level
    }
}

final class DisplayClock: NSObject {
    private var timer: Timer?
    private var last = 0.0
    var onFrame: ((Double) -> Void)?

    func start() {
        stop()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let dt = self.last == 0 ? 1.0 / 60.0 : min(0.05, max(0.001, now - self.last))
            self.last = now
            self.onFrame?(dt)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        last = 0
    }

    deinit { timer?.invalidate() }
}
