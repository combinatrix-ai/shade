import AppKit
import Combine
import ServiceManagement
import ShadeCore

final class AppModel: ObservableObject {
    @Published private(set) var session = Session()
    @Published var now = Date()
    @Published var error: String?
    @Published var keyboardIssue: String?
    @Published var delay: Double {
        didSet {
            if !demo {
                UserDefaults.standard.set(delay, forKey: "delay")
            }; reserveIfPending()
        }
    }

    @Published var shortcut: Shortcut {
        didSet {
            if !demo {
                UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: "hotkey")
            }
            configureKeyboard()
        }
    }

    @Published var wakeOnTouch: Bool {
        didSet {
            if !demo {
                UserDefaults.standard.set(wakeOnTouch, forKey: "wakeOnTouch")
            }
        }
    }

    @Published var onlyOnPowerAdapter: Bool {
        didSet {
            if !demo {
                UserDefaults.standard.set(onlyOnPowerAdapter, forKey: "onlyOnPowerAdapter")
                enforcePowerPolicy()
            }
        }
    }

    @Published private(set) var adapterConnected = true
    @Published private(set) var waitingForPower = false
    @Published var recording = false
    @Published var loginEnabled = false
    private let awake = AwakeHold()
    private let activity = PhysicalActivity()
    private let keyboard = KeyboardListener()
    private var brightness: Brightness?
    private var snapshot: (display: UInt32, value: Float)?
    private var restoreGuard: RestoreGuard?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var enabledAt: Date?
    var demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
        onlyOnPowerAdapter = UserDefaults.standard.object(forKey: "onlyOnPowerAdapter") as? Bool ?? true
        wakeOnTouch = UserDefaults.standard.bool(forKey: "wakeOnTouch")
        let savedDelay = UserDefaults.standard.double(forKey: "delay")
        delay = [30.0, 60, 180, 300].contains(savedDelay) ? savedDelay : 60
        shortcut = UserDefaults.standard.data(forKey: "hotkey").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .initial
        keyboard.action = { [weak self] in guard self?.recording == false else { return }; self?.shortcutAction() }
        adapterConnected = demo || PowerSupply.isOnAdapter()
        configureKeyboard()
        loginEnabled = SMAppService.mainApp.status == .enabled
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.disable() })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.disable() })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.recording, !self.isOn, keyboardIssue != nil else { return }; configureKeyboard()
        })
    }

    var isOn: Bool {
        session.isOn
    }

    var isDark: Bool {
        session.phase == .dark
    }

    var keyLabel: String {
        shortcut.label
    }

    var title: String {
        switch session.phase {
        case .off: return waitingForPower ? "Waiting for power adapter" : (blockedByPower ? "Needs a power adapter" : "Ready to dim")
        case .pending: let t = session.remaining(now: now); return String(format: "Dimming in %d:%02d", t / 60, t % 60)
        case .dark: return "Display dimmed"
        }
    }

    var delayLabel: String { delay == 30 ? "30 sec" : "\(Int(delay / 60)) min" }

    var needsBrightnessRecovery: Bool { snapshot != nil && error != nil }

    func retryRestore() {
        if restore() { error = nil }
    }

    func allowOnBattery() {
        onlyOnPowerAdapter = false
        if !isOn { enable() }
    }

    func captureShortcut(_ candidate: Shortcut) -> String? {
        if !demo {
            if isDark, !restore() { return "Restore the display before changing the shortcut." }
            if keyboard.configure(shortcut: candidate) != nil {
                keyboardIssue = keyboard.configure(shortcut: shortcut)
                if keyboardIssue != nil { disable() }
                return candidate.label + " is unavailable. Try another shortcut."
            }
        }
        shortcut = candidate
        return keyboardIssue
    }

    var actionLabel: String {
        switch session.phase { case .off: return waitingForPower ? "Turn Off" : "Turn On"; case .pending: return "Dim Now"; case .dark: return "Restore Display" }
    }

    func toggle() {
        (isOn || waitingForPower) ? disable() : enable()
    }

    var blockedByPower: Bool {
        !demo && onlyOnPowerAdapter && !adapterConnected
    }

    var enableControlDisabled: Bool {
        blockedByPower && !waitingForPower && !isOn
    }

    private var powerPermitsSession: Bool {
        demo || !onlyOnPowerAdapter || PowerSupply.isOnAdapter()
    }

    private func enforcePowerPolicy() {
        let connected = demo || PowerSupply.isOnAdapter()
        if adapterConnected != connected { adapterConnected = connected }
        if blockedByPower {
            if isOn {
                disable()
                waitingForPower = true
            }
        } else if waitingForPower {
            waitingForPower = false
            enable()
        }
    }

    func enable() {
        if snapshot != nil, !restore() { return }
        error = nil
        guard powerPermitsSession else {
            enforcePowerPolicy()
            return
        }
        configureKeyboard()
        guard demo || keyboard.ready else { error = keyboardIssue ?? "Set a shortcut before turning on Shade."; return }
        do {
            if !demo {
                let service = try Brightness()
                let id = try service.internalDisplay()
                _ = try service.get(id)
                brightness = service
                try activity.start()
                try awake.start()
            }
            now = Date()
            enabledAt = now
            session.enable(now: now, delay: delay)
        } catch { self.error = error.localizedDescription; awake.stop(); activity.stop() }
    }

    func disable() {
        waitingForPower = false
        // Always release sleep prevention, even if brightness recovery fails.
        // Keep the armed guardian/snapshot available for a recovery retry.
        _ = restore()
        awake.stop(); activity.stop(); enabledAt = nil; session.disable()
    }

    func primaryAction() {
        switch session.phase { case .off: toggle(); case .pending: dim(); case .dark: _ = restore() }
    }

    func shortcutAction() {
        guard isOn else { return }; if isDark {
            _ = restore()
        } else {
            reserve()
        }
    }

    func reserve() {
        now = Date()
        session.reserve(now: now, delay: delay)
    }

    private func reserveIfPending() {
        if case .pending = session.phase {
            reserve()
        }
    }

    func dim() {
        guard isOn, !isDark else { return }
        guard powerPermitsSession else { enforcePowerPolicy(); return }
        error = nil
        if demo {
            session.didDim(); return
        }
        guard keyboard.ready else { error = "Dimming stopped: shortcut unavailable."; disable(); return }
        do {
            guard let brightness else { throw ShadeFailure(message: "Brightness control is unavailable.") }
            let id = try brightness.internalDisplay(), original = try brightness.get(id)
            guard original > 0 else { throw ShadeFailure(message: "Display is already dimmed. Increase brightness and try again.") }
            let guardian = RestoreGuard()
            try guardian.start(display: id, brightness: original)
            snapshot = (id, original); restoreGuard = guardian
            // Consume activity preceding Dim Now so the click that dimmed the
            // display cannot be mistaken for a subsequent wake gesture.
            guard activity.sample() != nil else {
                throw ShadeFailure(message: "Hardware activity detection is unavailable.")
            }
            try brightness.set(id, 0)
            // Ignore the remainder of the dimming gesture, including events
            // sampled after the grace period but originating within it.
            activity.suppressDimmingGesture()
            session.didDim()
        } catch { self.error = error.localizedDescription; disable() }
    }

    @discardableResult func restore() -> Bool {
        if let snapshot {
            do {
                guard let brightness else { return false }
                try brightness.set(snapshot.display, snapshot.value)
                restoreGuard?.finish(); restoreGuard = nil
                self.snapshot = nil
            } catch { self.error = "Could not restore brightness. Use your brightness keys.\n" + error.localizedDescription; return false }
        }
        now = Date()
        session.didRestore(now: now, delay: delay)
        return true
    }

    func configureKeyboard() {
        guard !demo else { keyboardIssue = nil; return }
        if isDark, !restore() {
            return
        }
        keyboardIssue = keyboard.configure(shortcut: shortcut)
        if keyboardIssue != nil, isOn {
            disable()
        }
    }

    func setLogin(_ enabled: Bool) {
        guard !demo else { loginEnabled = enabled; return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled, !loginEnabled {
                error = "Allow Shade in System Settings → Login Items."
            }
        } catch { self.error = error.localizedDescription }
    }

    private func tick() {
        now = Date()
        enforcePowerPolicy()
        if isOn, !demo, !keyboard.ready || !awake.isRunning || (isDark && restoreGuard?.isRunning != true) {
            error = "Shade stopped: shortcut or sleep prevention unavailable."
            disable()
            return
        }
        if let enabledAt, now.timeIntervalSince(enabledAt) >= 28790 {
            disable(); return
        }
        if isOn, !demo {
            guard let active = activity.sample() else {
                error = "Shade stopped: hardware activity detection unavailable."
                disable()
                return
            }
            switch session.activityResponse(detected: active, wakeOnTouch: wakeOnTouch) {
            case .none: break
            case .postpone: reserve()
            case .restore:
                guard restore() else { return }
            }
            // A brightness-key escape restores the screen outside Shade. Adopt that
            // brightness and re-arm auto dim without overwriting the user's choice.
            if isDark, let snapshot, let brightness,
               let current = try? brightness.get(snapshot.display), current > 0
            {
                restoreGuard?.finish(); restoreGuard = nil
                self.snapshot = nil
                session.didRestore(now: now, delay: delay)
            }
        }
        if session.isDue(now: now) {
            dim()
        }
    }

    func shutdown() {
        _ = restore(); restoreGuard?.finish(); restoreGuard = nil; awake.stop(); activity.stop(); keyboard.stop()
    }
}
