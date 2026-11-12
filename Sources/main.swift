import AppKit
import AVFoundation
import CoreAudio
import Foundation
import ObjectiveC

// Room-mic rave driver for the PROLED XDR lid logo.
// LogoLight's Sound effect hears what the Mac is playing. This hears the room,
// so music from speakers flashes the logo like a rave light.
// On a Mac without the logo it prints the levels and does not touch hardware.

struct LogoCommand: Equatable {
    var key: String
    var value: Double
    var keyboard = false
}

/// The exact writes the lid LED accepts. A repeated DisplayLogicalState is ignored by
/// corebrightnessd, so a second kick has to flip away and back or the logo never flashes again.
enum LogoPlan {
    static func enable() -> LogoCommand { LogoCommand(key: "LEBacklightMode", value: 2) }

    static func flash(lit: Bool, seconds: Double, headingLit: Bool?) -> (cmds: [LogoCommand], heading: Bool) {
        var cmds: [LogoCommand] = []
        var heading = headingLit
        if heading == lit {
            cmds.append(LogoCommand(key: "LEPWMFactorFadeDuration", value: 1e9))
            cmds.append(LogoCommand(key: "DisplayLogicalState", value: lit ? 1 : 2))
            heading = !lit
            if lit { cmds.append(LogoCommand(key: "DisplayLogicalState", value: 2, keyboard: true)) }
        }
        cmds.append(LogoCommand(key: "LEPWMFactorFadeDuration", value: seconds))
        cmds.append(LogoCommand(key: "DisplayLogicalState", value: lit ? 2 : 1))
        if !lit { cmds.append(LogoCommand(key: "DisplayLogicalState", value: 2, keyboard: true)) }
        return (cmds, lit)
    }

    /// A fade that does not restart if the logo is already heading that way. Restarting
    /// every frame is what made the lid jitter.
    static func glide(lit: Bool, seconds: Double, headingLit: Bool?) -> (cmds: [LogoCommand], heading: Bool) {
        if headingLit == lit { return ([], lit) }
        var cmds = [
            LogoCommand(key: "LEPWMFactorFadeDuration", value: seconds),
            LogoCommand(key: "DisplayLogicalState", value: lit ? 2 : 1),
        ]
        if !lit { cmds.append(LogoCommand(key: "DisplayLogicalState", value: 2, keyboard: true)) }
        return (cmds, lit)
    }

    static func holdStart(up: Bool) -> (cmds: [LogoCommand], heading: Bool) {
        var cmds = [
            LogoCommand(key: "LEPWMFactorFadeDuration", value: 0.05),
            LogoCommand(key: "DisplayLogicalState", value: up ? 2 : 1),
        ]
        if !up { cmds.append(LogoCommand(key: "DisplayLogicalState", value: 2, keyboard: true)) }
        return (cmds, up)
    }

    static func holdLock(wasUp: Bool) -> (cmds: [LogoCommand], heading: Bool) {
        return ([
            LogoCommand(key: "LEPWMFactorFadeDuration", value: 1e9),
            LogoCommand(key: "DisplayLogicalState", value: wasUp ? 1 : 2),
            LogoCommand(key: "DisplayLogicalState", value: 2, keyboard: true),
        ], !wasUp)
    }

    static func restore() -> [LogoCommand] {
        [
            LogoCommand(key: "LEPWMFactorFadeDuration", value: 0.3),
            LogoCommand(key: "DisplayLogicalState", value: 2),
            LogoCommand(key: "DisplayLogicalState", value: 2, keyboard: true),
            LogoCommand(key: "LEPWMFactorFadeDuration", value: 0),
        ]
    }
}

/// corebrightnessd's measured rule: a DisplayLogicalState write is ignored unless it changes
/// direction. A 1e9 s fade freezes the logo. Anything else eases toward dark or lit.
struct FakeLogo {
    var factor = 1.0
    var headingLit: Bool? = true
    var duration = 0.3
    var keyboardLit = true
    var ignoredRepeats = 0
    private var targetLit = true

    mutating func apply(_ command: LogoCommand, dt: Double = 0.04) {
        if command.keyboard {
            keyboardLit = command.value == 2
            return
        }
        switch command.key {
        case "LEBacklightMode":
            break
        case "LEPWMFactorFadeDuration":
            duration = command.value
        case "DisplayLogicalState":
            let lit = command.value == 2
            if headingLit == lit {
                ignoredRepeats += 1
                return
            }
            headingLit = lit
            targetLit = lit
            if duration >= 1e8 { return }
            let steps = max(Int(dt / 0.01), 1)
            for _ in 0..<steps {
                let dest = targetLit ? 1.0 : 0.0
                let portion = min(0.01 / max(duration, 0.01), 1)
                factor += (dest - factor) * portion
            }
        default:
            fatalError("unknown key \(command.key)")
        }
    }
}

struct RaveMeter: Sendable {
    var release = 0.09
    var ceilingDecay = 3.0
    var range = 18.0
    var silence = -55.0
    var floor = -42.0

    private(set) var envelope = 0.0
    private(set) var ceiling = 0.0
    private(set) var loudness = 0.0
    private(set) var beat = false

    mutating func add(rms: Double, seconds: Double, kick: Double? = nil) -> Double {
        let dt = max(seconds, 0)
        let level = min(max(kick ?? rms, 0), 1)
        envelope = max(level, envelope * exp(-dt / release))
        ceiling = max(envelope, ceiling * exp(-dt / ceilingDecay), amplitude(dB: floor))
        if envelope <= amplitude(dB: silence) {
            loudness = 0
        } else {
            let dB = 20 * log10(max(envelope / ceiling, 1e-9))
            loudness = min(max(1 + dB / range, 0), 1)
        }
        beat = loudness > 0.7
        return loudness
    }

    static func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum = 0.0
        for sample in samples { sum += Double(sample) * Double(sample) }
        return (sum / Double(samples.count)).squareRoot()
    }

    private func amplitude(dB: Double) -> Double { pow(10, dB / 20) }
}

struct SmoothFollower {
    enum Move: Equatable {
        case rise(Double)
        case fall(Double)
    }

    var riseTime = 0.12
    var fallTime = 0.22
    var deadband = 0.1
    var minGap = 0.09
    var shown = 0.0
    private var motion = 0
    private var since = 1.0

    mutating func step(target: Double, dt: Double) -> Move? {
        let dt = max(dt, 0)
        let target = min(max(target, 0), 1)
        since += dt
        if motion > 0 { shown = min(1, shown + dt / riseTime) }
        if motion < 0 { shown = max(0, shown - dt / fallTime) }
        let gap = target - shown
        if motion != 0, abs(gap) < deadband {
            motion = 0
            return nil
        }
        if motion > 0, gap >= -deadband { return nil }
        if motion < 0, gap <= deadband { return nil }
        if abs(gap) < deadband || since < minGap { return nil }
        since = 0
        if gap > 0 {
            motion = 1
            return .rise(riseTime)
        }
        motion = -1
        return .fall(fallTime)
    }
}

final class LogoBus {
    private let client: NSObject
    private let copySelector = NSSelectorFromString("copyPropertyForKey:")
    private let setSelector = NSSelectorFromString("setProperty:forKey:")
    private let keyboardSelector = NSSelectorFromString("setProperty:withKey:keyboardID:")
    private typealias CopyFn = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
    private typealias SetFn = @convention(c) (AnyObject, Selector, AnyObject, NSString) -> Bool
    private typealias KeyFn = @convention(c) (AnyObject, Selector, AnyObject, NSString, UInt64) -> Bool
    private let copyFn: CopyFn
    private let setFn: SetFn
    private let keyFn: KeyFn?
    private let keyboardIDs: [UInt64]
    private var headingLit: Bool?
    private var level = 0.0
    private var follower = SmoothFollower()
    private var enabled = false

    static func open() -> LogoBus? {
        let path = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
        guard dlopen(path, RTLD_LAZY) != nil,
              let type = NSClassFromString("BrightnessSystemClient") as? NSObject.Type
        else { return nil }
        let bus = LogoBus(type: type)
        guard bus.hasLogo else { return nil }
        return bus
    }

    private init(type: NSObject.Type) {
        client = type.init()
        copyFn = unsafeBitCast(client.method(for: copySelector), to: CopyFn.self)
        setFn = unsafeBitCast(client.method(for: setSelector), to: SetFn.self)
        if type.instancesRespond(to: keyboardSelector) {
            keyFn = unsafeBitCast(client.method(for: keyboardSelector), to: KeyFn.self)
        } else {
            keyFn = nil
        }
        keyboardIDs = []
    }

    var hasLogo: Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        task.arguments = ["-r", "-n", "bklb-backlight@0", "-w0"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.contains("bklb-backlight") == true
    }

    func setLevel(_ target: Double, dt: Double = 1.0 / 60.0) {
        let target = min(max(target, 0), 1)
        if !enabled {
            _ = set(LogoPlan.enable().value, key: LogoPlan.enable().key)
            enabled = true
        }
        guard let move = follower.step(target: target, dt: dt) else {
            level = follower.shown
            return
        }
        switch move {
        case let .rise(seconds):
            let planned = LogoPlan.glide(lit: true, seconds: seconds, headingLit: headingLit)
            apply(planned.cmds)
            headingLit = planned.heading
        case let .fall(seconds):
            let planned = LogoPlan.glide(lit: false, seconds: seconds, headingLit: headingLit)
            apply(planned.cmds)
            headingLit = planned.heading
        }
        level = follower.shown
    }

    func restore() {
        apply(LogoPlan.restore())
        headingLit = true
    }

    private func flash(lit: Bool, seconds: Double) {
        let planned = LogoPlan.flash(lit: lit, seconds: seconds, headingLit: headingLit)
        apply(planned.cmds)
        headingLit = planned.heading
    }

    private func hold(at target: Double) {
        let up = target >= level
        let start = LogoPlan.holdStart(up: up)
        apply(start.cmds)
        headingLit = start.heading
        let deadline = Date().addingTimeInterval(0.08)
        while Date() < deadline {
            if let factor = factor, (up && factor >= target) || (!up && factor <= target) { break }
            Thread.sleep(forTimeInterval: 0.008)
        }
        let lock = LogoPlan.holdLock(wasUp: up)
        apply(lock.cmds)
        headingLit = lock.heading
    }

    private func apply(_ commands: [LogoCommand]) {
        for command in commands {
            if command.keyboard {
                tellKeyboard(lit: command.value == 2)
            } else {
                _ = set(command.value, key: command.key)
            }
        }
    }

    private var factor: Double? {
        guard let state = copy("LEPWMState") as? [String: Any],
              let number = state["Factor"] as? NSNumber else { return nil }
        return number.doubleValue
    }

    @discardableResult
    private func set(_ value: Double, key: String) -> Bool {
        var ok = false
        let caught = LogoCatch {
            ok = self.setFn(self.client, self.setSelector, NSNumber(value: value), key as NSString)
        }
        return caught && ok
    }

    private func copy(_ key: String) -> Any? {
        copyFn(client, copySelector, key as NSString)?.takeRetainedValue()
    }

    private func tellKeyboard(lit: Bool) {
        guard let keyFn else { return }
        let value = NSNumber(value: lit ? 2 : 1)
        for id in keyboardIDs {
            _ = keyFn(client, keyboardSelector, value, "DisplayLogicalState" as NSString, id)
        }
    }
}

func selfTest() -> Int {
    var meter = RaveMeter()
    var flashes = 0
    var darkGaps = 0
    // Four kicks, 120 BPM, with silence between them.
    let kick = Array(repeating: Float(0.5), count: 80) + Array(repeating: Float(0.01), count: 400)
    for beat in 0..<4 {
        let level = meter.add(rms: RaveMeter.rms(kick), seconds: 0.02)
        if level > 0.8 { flashes += 1 }
        for _ in 0..<8 {
            let gap = meter.add(rms: 0.005, seconds: 0.05)
            if gap < 0.08 { darkGaps += 1 }
        }
        if beat == 0 && !meter.beat && level < 0.5 {
            fputs("first hit did not register\n", stderr)
            return 1
        }
    }
    guard flashes >= 3 else {
        fputs("flashes \(flashes) gaps \(darkGaps)\n", stderr)
        return 1
    }
    print("self-test ok flashes \(flashes) dark-gaps \(darkGaps)")
    var follower = SmoothFollower()
    var writes = 0
    for _ in 0..<50 {
        if follower.step(target: 0.55, dt: 0.03) != nil { writes += 1 }
    }
    var beatWrites = 0
    follower = SmoothFollower()
    for _ in 0..<8 {
        for _ in 0..<4 {
            if follower.step(target: 1, dt: 0.03) != nil { beatWrites += 1 }
        }
        for _ in 0..<14 {
            if follower.step(target: 0, dt: 0.03) != nil { beatWrites += 1 }
        }
    }
    guard writes <= 2, beatWrites <= 16 else {
        fputs("smoothness failed steady \(writes) beats \(beatWrites)\n", stderr)
        return 1
    }
    print("smoothness ok steady-writes \(writes) beat-writes \(beatWrites)")
    var loud = RaveMeter()
    let high = loud.add(rms: 0.5, seconds: 0.02)
    var quiet = RaveMeter()
    let low = quiet.add(rms: 0.005, seconds: 0.2)
    guard high > low else {
        fputs("level failed high \(high) low \(low)\n", stderr)
        return 1
    }
    print("level ok")
    return 0
}

func theoryTest() -> Int {
    var logo = FakeLogo()
    var meter = RaveMeter()
    var heading: Bool? = true
    var brightKicks = 0
    var darkGaps = 0
    var keyboardDrops = 0
    for _ in 0..<8 {
        logo.apply(LogoPlan.enable())
        let planned = LogoPlan.flash(lit: true, seconds: 0.03, headingLit: heading)
        heading = planned.heading
        for command in planned.cmds { logo.apply(command, dt: 0.03) }
        if logo.factor > 0.7 { brightKicks += 1 }
        if !logo.keyboardLit { keyboardDrops += 1 }
        for _ in 0..<6 {
            _ = meter.add(rms: 0.004, seconds: 0.04)
            let planned = LogoPlan.flash(lit: false, seconds: 0.04, headingLit: heading)
            heading = planned.heading
            for command in planned.cmds { logo.apply(command, dt: 0.04) }
        }
        if logo.factor < 0.2 { darkGaps += 1 }
        if !logo.keyboardLit { keyboardDrops += 1 }
    }
    var naive = FakeLogo(factor: 0.2, headingLit: false)
    naive.apply(LogoCommand(key: "LEPWMFactorFadeDuration", value: 0.03))
    naive.apply(LogoCommand(key: "DisplayLogicalState", value: 2))
    let before = naive.factor
    naive.apply(LogoCommand(key: "DisplayLogicalState", value: 2))
    let repeatIgnored = naive.ignoredRepeats == 1 && abs(naive.factor - before) < 0.001

    var held = FakeLogo(factor: 0.1, headingLit: false)
    let start = LogoPlan.holdStart(up: true)
    for command in start.cmds { held.apply(command, dt: 0.05) }
    let rising = held.factor
    let lock = LogoPlan.holdLock(wasUp: true)
    for command in lock.cmds { held.apply(command, dt: 0.2) }
    let frozen = abs(held.factor - rising) < 0.02 && held.keyboardLit

    var restored = logo
    for command in LogoPlan.restore() { restored.apply(command, dt: 0.05) }
    let restoredOK = restored.duration == 0 && restored.headingLit == true && restored.keyboardLit

    let api = probeBrightnessAPI()
    let ok = brightKicks == 8 && darkGaps == 8 && keyboardDrops == 0 && repeatIgnored && frozen && restoredOK && api.contains("readable")
    if !ok {
        fputs("theory failed kicks \(brightKicks) gaps \(darkGaps) keyboard \(keyboardDrops) repeat \(repeatIgnored) hold \(frozen) restore \(restoredOK) api \(api)\n", stderr)
        return 1
    }
    print("theory ok kicks \(brightKicks)/8 dark-gaps \(darkGaps)/8 keyboard-stayed-on repeat-ignored hold-froze restore-clean api \(api)")
    return 0
}

func probeBrightnessAPI() -> String {
    let path = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
    guard dlopen(path, RTLD_LAZY) != nil,
          let type = NSClassFromString("BrightnessSystemClient") as? NSObject.Type
    else { return "missing" }
    let selector = NSSelectorFromString("copyPropertyForKey:")
    guard type.instancesRespond(to: selector) else { return "no-reader" }
    typealias CopyFn = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
    let client = type.init()
    let copy = unsafeBitCast(client.method(for: selector), to: CopyFn.self)
    let value = copy(client, selector, "LEBacklightMode" as NSString)?.takeRetainedValue()
    if value == nil { return "readable-nil" }
    return "readable"
}

enum MicList {
    static func devices() -> [(id: UInt32, name: String)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasInput(id) else { return nil }
            return (id, name(id))
        }
    }

    static func defaultID() -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr, id != 0 else {
            return nil
        }
        return id
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private static func name(_ id: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer))
        }
        guard status == noErr else { return "Microphone" }
        return name as String
    }
}

@_silgen_name("LogoCatch")
func LogoCatch(_ block: @convention(block) () -> Void) -> Bool

final class RoomEar {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var latest = 0.0
    private var latestKick = 0.0
    private var low = 0.0
    var onLevel: ((Double) -> Void)?

    private var tapInstalled = false

    func start(device: UInt32? = nil) throws {
        let input = engine.inputNode
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        if let device, let unit = input.audioUnit {
            var id = AudioDeviceID(device)
            let status = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                throw NSError(domain: "logo-rave", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "could not switch microphone"])
            }
        }
        let candidates = [input.outputFormat(forBus: 0), input.inputFormat(forBus: 0)]
        var installed = false
        for format in candidates where format.sampleRate > 0 && format.channelCount > 0 {
            let ok = LogoCatch {
                input.installTap(onBus: 0, bufferSize: 256, format: format) { [weak self] buffer, _ in
                    guard let self else { return }
                    let frames = Int(buffer.frameLength)
                    guard buffer.format.commonFormat == .pcmFormatFloat32,
                          let data = buffer.floatChannelData,
                          frames > 0, frames < 8192 else { return }
                    let pointer = data[0]
                    var sum = 0.0
                    for i in 0..<frames {
                        let sample = Double(pointer[i])
                        sum += sample * sample
                    }
                    let rms = (sum / Double(frames)).squareRoot()
                    self.lock.lock()
                    self.latest = rms
                    self.latestKick = rms
                    self.lock.unlock()
                }
            }
            if ok {
                installed = true
                break
            }
            input.removeTap(onBus: 0)
        }
        guard installed else {
            throw NSError(domain: "logo-rave", code: 2, userInfo: [NSLocalizedDescriptionKey: "microphone tap failed"])
        }
        tapInstalled = true
        engine.prepare()
        var started = false
        let caught = LogoCatch {
            do {
                try self.engine.start()
                started = true
            } catch {
                started = false
            }
        }
        if !caught || !started {
            input.removeTap(onBus: 0)
            tapInstalled = false
            throw NSError(domain: "logo-rave", code: 3, userInfo: [NSLocalizedDescriptionKey: "microphone did not start"])
        }
    }

    func rms() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func kick() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return latestKick
    }

    private func kickEnergy(_ buffer: AVAudioPCMBuffer, channels: Int, frames: Int) -> Double {
        guard buffer.format.sampleRate > 0, let data = buffer.floatChannelData, frames > 0, channels > 0 else { return 0 }
        let blend = exp(-2 * Double.pi * 140 / buffer.format.sampleRate)
        var sum = 0.0
        for i in 0..<frames {
            var sample = 0.0
            for c in 0..<channels { sample += Double(data[c][i]) }
            sample /= Double(channels)
            low = blend * low + (1 - blend) * sample
            sum += low * low
        }
        return (sum / Double(frames)).squareRoot()
    }

    func stop() { engine.stop() }
}

let args = CommandLine.arguments
if args.contains("--self-test") { exit(Int32(selfTest())) }
if args.contains("--theory") { exit(Int32(theoryTest())) }

let simulate = args.contains("--simulate") || LogoBus.open() == nil
let bus = simulate ? nil : LogoBus.open()
let preview = args.contains("--preview")
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let ui = RaveWindow()

let ear = RoomEar()
var micOn = false
let chosen = MicList.defaultID()
ui.setMics(MicList.devices(), selected: chosen)
ui.onMic = { id in
    do {
        try ear.start(device: id)
        micOn = true
    } catch {
        micOn = false
    }
}
if !preview {
    DispatchQueue.main.async {
        do {
            try ear.start()
            micOn = true
        } catch {
            micOn = false
        }
    }
}

var meter = RaveMeter()
var shownLevel = 0.0
let started = Date()
let clock = DisplayClock()
clock.onFrame = { dt in
    let elapsed = Date().timeIntervalSince(started)
    let rms: Double
    let kick: Double
    if args.contains("--bright") {
        rms = 0.6
        kick = 0.6
    } else if preview || !micOn {
        let beatOn = elapsed.truncatingRemainder(dividingBy: 0.5) < 0.08
        rms = beatOn ? 0.6 : 0.004
        kick = rms
    } else {
        rms = ear.rms()
        kick = ear.kick()
    }
    let level = meter.add(rms: rms, seconds: dt, kick: kick)
    let follow = 1 - exp(-dt / 0.035)
    shownLevel += (level - shownLevel) * follow
    bus?.setLevel(level, dt: dt)
    ui.show(level: shownLevel)
}
let delegate = RaveApp()
delegate.onQuit = {
    bus?.restore()
    ear.stop()
}
app.delegate = delegate
clock.start()
if preview || args.contains("--bright") {
    DispatchQueue.main.async { ui.showPopover() }
}
app.run()
