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

/// Native button semantics with an unobtrusive visual treatment over the artwork.
final class LogoToggleButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        if window?.firstResponder === self {
            NSColor.controlAccentColor.withAlphaComponent(0.7).setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 22, yRadius: 22)
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}

final class RavePanel: NSView {
    var level = 0.0
    var ripples = RippleField()
    var lightEnabled = true
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
        title.draw(at: NSPoint(x: (bounds.width - titleSize.width) / 2, y: 22))

        let lid = NSRect(x: 28, y: 52, width: bounds.width - 56, height: 168)
        let shell = NSBezierPath(roundedRect: lid, xRadius: 22, yRadius: 22)
        NSGradient(starting: NSColor(white: 0.14, alpha: 1), ending: NSColor(white: 0.085, alpha: 1))?
            .draw(in: shell, angle: 90)

        NSGraphicsContext.saveGraphicsState()
        shell.addClip()
        drawRipples(in: lid)
        drawGlowingLogo(in: lid, level: level)
        NSGraphicsContext.restoreGraphicsState()

        NSColor(white: 1, alpha: 0.08).setStroke()
        shell.lineWidth = 1
        shell.stroke()

        let stateText = NSAttributedString(string: lightEnabled ? "Light on" : "Light off", attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ])
        stateText.draw(at: NSPoint(x: (bounds.width - stateText.size().width) / 2, y: 231))
        let statusText = NSAttributedString(string: status, attributes: [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor,
        ])
        statusText.draw(at: NSPoint(x: (bounds.width - statusText.size().width) / 2, y: 254))
        let meter = NSRect(x: 48, y: 278, width: bounds.width - 96, height: 3)
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
        mark.draw(in: box, from: .zero, operation: .sourceOver, fraction: lightEnabled ? 0.55 + 0.45 * level : 0.18, respectFlipped: true, hints: nil)
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
    let panel = RavePanel(frame: NSRect(x: 0, y: 0, width: 300, height: 328))
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let popover = NSPopover()
    let quit = NSButton(title: "Quit", target: nil, action: nil)
    var onLightEnabled: ((Bool) -> Void)?
    let logoToggle = LogoToggleButton(title: "", target: nil, action: nil)

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
        quit.image = SymbolStyle.image("rectangle.portrait.and.arrow.right", pointSize: 11, description: "Quit Logo Rave")
        quit.imagePosition = .imageLeading
        quit.isBordered = false
        quit.font = .systemFont(ofSize: 11)
        quit.contentTintColor = .secondaryLabelColor
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = .command
        quit.frame = NSRect(x: 214, y: 297, width: 66, height: 22)
        panel.addSubview(quit)
        let hint = NSTextField(labelWithString: "Click logo or press Space")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        hint.frame = NSRect(x: 20, y: 301, width: 178, height: 16)
        panel.addSubview(hint)
        logoToggle.frame = NSRect(x: 96, y: 88, width: 108, height: 96)
        logoToggle.setButtonType(.pushOnPushOff)
        logoToggle.isBordered = false
        logoToggle.state = .on
        logoToggle.target = self
        logoToggle.action = #selector(lightChanged)
        logoToggle.keyEquivalent = " "
        logoToggle.keyEquivalentModifierMask = []
        logoToggle.setAccessibilityLabel("Logo light, on")
        logoToggle.setAccessibilityHelp("Toggle the logo light and microphone. Space toggles while this panel is open.")
        logoToggle.toolTip = "Turn light off · Space"
        panel.addSubview(logoToggle)
    }

    @objc private func lightChanged() {
        let enabled = logoToggle.state == .on
        panel.lightEnabled = enabled
        logoToggle.setAccessibilityLabel(enabled ? "Logo light, on" : "Logo light, off")
        logoToggle.toolTip = enabled ? "Turn light off · Space" : "Turn light on · Space"
        panel.needsDisplay = true
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
