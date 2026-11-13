import AppKit

/// Owns the app session. UI callbacks and frame updates run on the main run loop;
/// RoomEar synchronizes its audio-thread samples separately.
private final class AudioStartTicket {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

final class RaveController {
    let delegate = RaveApp()
    private let ui = RaveWindow()
    private let ear = RoomEar()
    private let clock = DisplayClock()
    private let audioQueue = DispatchQueue(label: "LogoRave.microphone", qos: .userInitiated)
    private var audioStart: AudioStartTicket?
    private var startingMicrophone = false
    private let bus: LogoBus?
    private let preview: Bool
    private let bright: Bool
    private var lightEnabled = true
    private var micOn = false
    private var selectedMic: UInt32?
    private var meter = RaveMeter()
    private var shownLevel = 0.0
    private var elapsed = 0.0
    private var lastMicrophoneAttempt = -Double.infinity

    init(arguments: [String]) {
        preview = arguments.contains("--preview")
        bright = arguments.contains("--bright")
        bus = arguments.contains("--simulate") ? nil : LogoBus.open()
        selectedMic = MicList.preferredID()
        ui.onLightEnabled = { [weak self] enabled in self?.setLightEnabled(enabled) }
        clock.onFrame = { [weak self] dt in self?.update(seconds: dt) }
        delegate.onQuit = { [weak self] in self?.stop() }
    }

    func start() {
        if !preview { startMicrophone() }
        clock.start()
        if preview || bright {
            DispatchQueue.main.async { [weak self] in self?.ui.showPopover() }
        }
    }

    private func startMicrophone() {
        lastMicrophoneAttempt = ProcessInfo.processInfo.systemUptime
        let devices = MicList.builtInDevices()
        if !devices.contains(where: { $0.id == selectedMic }) {
            selectedMic = MicList.preferredID()
        }
        audioStart?.cancel()
        let ticket = AudioStartTicket()
        audioStart = ticket
        startingMicrophone = true
        micOn = false
        let device = selectedMic
        let ear = self.ear
        audioQueue.async { [weak self] in
            guard !ticket.isCancelled else { return }
            var failure: Error?
            do { try ear.start(device: device) } catch { failure = error }
            if ticket.isCancelled { ear.stop(); return }
            let message = failure?.localizedDescription
            DispatchQueue.main.async { [weak self] in
                guard let self, self.audioStart === ticket, self.lightEnabled else { return }
                self.startingMicrophone = false
                self.micOn = message == nil
                self.lastMicrophoneAttempt = ProcessInfo.processInfo.systemUptime
                if let message { NSLog("Logo Rave microphone unavailable: %@", message) }
            }
        }
    }

    private func setLightEnabled(_ enabled: Bool) {
        guard lightEnabled != enabled else { return }
        lightEnabled = enabled
        meter = RaveMeter()
        shownLevel = 0
        if enabled {
            if !preview { startMicrophone() }
        } else {
            audioStart?.cancel()
            audioStart = nil
            startingMicrophone = false
            micOn = false
            bus?.turnOff()
            let ear = self.ear
            audioQueue.async { ear.stop() }
            ui.panel.status = "Microphone paused"
            ui.show(level: 0, animated: false)
        }
    }

    private func update(seconds dt: Double) {
        elapsed += dt
        guard lightEnabled else { return }
        if !preview && !bright && !startingMicrophone && (ear.needsRestart || !ear.hasFreshAudio) &&
            ProcessInfo.processInfo.systemUptime - lastMicrophoneAttempt >= 3 {
            startMicrophone()
        }
        ui.panel.status = startingMicrophone ? "Starting built-in microphone…" :
            (!preview && !bright && (!micOn || !ear.hasFreshAudio)
                ? "Built-in microphone unavailable" : "Listening · built-in microphone")
        let rms: Double
        if bright {
            rms = 0.6
        } else if preview {
            rms = elapsed.truncatingRemainder(dividingBy: 0.5) < 0.08 ? 0.6 : 0.004
        } else {
            rms = micOn ? ear.rms() : 0
        }
        let level = meter.add(rms: rms, seconds: dt)
        shownLevel += (level - shownLevel) * (1 - exp(-dt / 0.035))
        bus?.setLevel(level, dt: dt)
        ui.show(level: shownLevel, seconds: dt)
    }

    private func stop() {
        clock.stop()
        audioStart?.cancel()
        audioQueue.sync { ear.stop() }
        bus?.restore()
    }
}
