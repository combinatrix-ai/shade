import AppKit
import Combine
import ServiceManagement
import ShadeCore

final class AppModel: ObservableObject {
    @Published private(set) var session = Session()
    @Published private(set) var autoLockSnapshot = AutoLockSnapshot()
    private let lockQueue = DispatchQueue(label: "shade.auto-lock", qos: .utility)
    private var lockReadGeneration = 0
    private var nextLockRead = Date.distantPast
    private var lockReadPending = false
    private var shuttingDown = false
    @Published var now = Date()
    @Published var error: String?
    @Published var keyboardIssue: String?
    @Published private(set) var delay: Double {
        didSet {
            if !demo {
                defaults.set(delay, forKey: "delay")
            }; reserveIfPending()
        }
    }

    @Published var shortcut: Shortcut {
        didSet {
            if !demo {
                defaults.set(try? JSONEncoder().encode(shortcut), forKey: "hotkey")
            }
            configureKeyboard()
        }
    }

    @Published var wakeOnTouch: Bool {
        didSet {
            if !demo {
                defaults.set(wakeOnTouch, forKey: "wakeOnTouch")
            }
        }
    }

    @Published var onlyOnPowerAdapter: Bool {
        didSet {
            if !demo {
                defaults.set(onlyOnPowerAdapter, forKey: "onlyOnPowerAdapter")
                enforcePowerPolicy()
            }
        }
    }

    @Published private(set) var adapterConnected = true
    @Published private(set) var waitingForPower = false
    @Published var editingDelay = false
    @Published var recording = false
    @Published var loginEnabled = false
    private let defaults: UserDefaults
    private let awake = AwakeHold()
    private let activity = PhysicalActivity()
    private let keyboard = KeyboardListener()
    private var brightness: Brightness?
    private var snapshot: [DisplaySnapshot]?
    private var knownDisplayIDs = Set<CGDirectDisplayID>()
    private var restoreGuard: RestoreGuard?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var enabledAt: Date?
    var demo: Bool

    init(demo: Bool = false, defaults: UserDefaults = .standard) {
        self.demo = demo
        self.defaults = defaults
        onlyOnPowerAdapter = defaults.object(forKey: "onlyOnPowerAdapter") as? Bool ?? true
        wakeOnTouch = defaults.bool(forKey: "wakeOnTouch")
        let savedDelay = defaults.double(forKey: "delay")
        delay = DimmingDelay.restoredSeconds(savedDelay)
        shortcut = defaults.data(forKey: "hotkey").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .initial
        keyboard.action = { [weak self] in guard self?.recording == false else { return }; self?.shortcutAction() }
        adapterConnected = demo || PowerSupply.isOnAdapter()
        configureKeyboard()
        refreshAutoLock()
        loginEnabled = SMAppService.mainApp.status == .enabled
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.disable() })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.disable() })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.recording, !self.isOn, keyboardIssue != nil else { return }; configureKeyboard()
        })
    }

    var autoLockStatus: AutoLockStatus {
        demo ? (isOn ? .prevented : .after(600)) : autoLockSnapshot.status
    }

    var autoLockDetail: String? {
        autoLockStatus == .prevented && !isOn ? "By another app" : nil
    }

    func refreshAutoLock(force: Bool = false) {
        guard !demo, !shuttingDown else { return }
        if force {
            lockReadGeneration += 1
            autoLockSnapshot = AutoLockSnapshot()
            nextLockRead = .distantPast
        }
        guard !lockReadPending, Date() >= nextLockRead else { return }
        lockReadPending = true
        let generation = lockReadGeneration
        lockQueue.async { [weak self] in
            let snapshot = AutoLockMonitor.read()
            DispatchQueue.main.async {
                guard let self, !self.shuttingDown else { return }
                self.lockReadPending = false
                guard generation == self.lockReadGeneration else { self.refreshAutoLock(); return }
                self.autoLockSnapshot = snapshot
                self.nextLockRead = Date().addingTimeInterval(5)
            }
        }
    }

    var isOn: Bool {
        session.isOn
    }

    var isDark: Bool {
        session.phase == .dark
    }

    var isClamshell: Bool {
        session.phase == .clamshell
    }

    var keyLabel: String {
        shortcut.label
    }

    var title: String {
        switch session.phase {
        case .off: return waitingForPower ? "Waiting for power adapter" : (blockedByPower ? "Needs a power adapter" : "Ready to dim")
        case .pending: let t = session.remaining(now: now); return String(format: "Dimming in %d:%02d", t / 60, t % 60)
        case .dark: return "All displays dimmed"
        case .clamshell: return "Clamshell mode"
        }
    }

    var displayDetail: String? {
        isClamshell ? "Keeping this Mac awake. The built-in display is already off." : nil
    }

    var delayLabel: String { "\(Int(delay / 60)) min" }

    var restoreHint: String {
        let hasHardwareBrightness = snapshot?.contains { snapshot in
            if case .brightness = snapshot.method { return true }
            return false
        } == true
        return hasHardwareBrightness ? "brightness-up or " + shortcut.label : shortcut.label
    }

    func setDelay(minutes: Int) {
        guard DimmingDelay.minutes.contains(minutes) else { return }
        delay = Double(minutes * 60)
        editingDelay = false
    }

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
        switch session.phase {
        case .off: return waitingForPower ? "Turn Off" : "Turn On"
        case .pending: return "Dim Now"
        case .dark: return "Restore Displays"
        case .clamshell: return "Turn Off"
        }
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
        if adapterConnected != connected {
            adapterConnected = connected
            refreshAutoLock(force: true)
        }
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
                let displays = service.onlineDisplayIDs()
                if displays.isEmpty, !ClamshellState.isClosed() {
                    throw ShadeFailure(message: "No online display found.")
                }
                brightness = service
                knownDisplayIDs = Set(displays)
                try activity.start()
                try awake.start()
            }
            now = Date()
            enabledAt = now
            if !demo, brightness?.onlineDisplayIDs().isEmpty == true {
                session.enableClamshell()
            } else {
                session.enable(now: now, delay: delay)
            }
            refreshAutoLock(force: true)
        } catch { self.error = error.localizedDescription; awake.stop(); activity.stop() }
    }

    func disable() {
        waitingForPower = false
        // Always release sleep prevention, even if brightness recovery fails.
        // Keep the armed guardian/snapshot available for a recovery retry.
        _ = restore()
        awake.stop(); activity.stop(); enabledAt = nil; session.disable()
        refreshAutoLock(force: true)
    }

    func primaryAction() {
        switch session.phase {
        case .off: toggle()
        case .pending: dim()
        case .dark: _ = restore()
        case .clamshell: disable()
        }
    }

    func shortcutAction() {
        guard isOn, !isClamshell else { return }; if isDark {
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
        guard isOn, !isDark, !isClamshell else { return }
        guard powerPermitsSession else { enforcePowerPolicy(); return }
        error = nil
        if demo {
            session.didDim(); return
        }
        guard keyboard.ready else { error = "Dimming stopped: shortcut unavailable."; disable(); return }
        do {
            guard let brightness else { throw ShadeFailure(message: "Brightness control is unavailable.") }
            let originals = try brightness.snapshots()
            guard !originals.isEmpty else {
                if ClamshellState.isClosed() {
                    session.enterClamshell()
                    return
                }
                throw ShadeFailure(message: "No online display found.")
            }
            let guardian = RestoreGuard()
            try guardian.start(snapshots: originals)
            snapshot = originals; restoreGuard = guardian
            // Consume activity preceding Dim Now so the click that dimmed the
            // display cannot be mistaken for a subsequent wake gesture.
            guard activity.sample() != nil else {
                throw ShadeFailure(message: "Hardware activity detection is unavailable.")
            }
            try brightness.dim(originals)
            knownDisplayIDs = Set(originals.map(\.id))
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
                try brightness.restore(snapshot)
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
        refreshAutoLock()
        refreshDisplayState()
        if isOn, !demo, !keyboard.ready || !awake.isRunning || (snapshot != nil && restoreGuard?.isRunning != true) {
            error = "Shade stopped: shortcut or sleep prevention unavailable."
            disable()
            return
        }
        if let enabledAt, now.timeIntervalSince(enabledAt) >= 28790 {
            disable(); return
        }
        if isOn, !demo, !isClamshell {
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
               brightness.hasHardwareBrightnessRestored(snapshot)
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

    private func refreshDisplayState() {
        guard !demo, let brightness else { return }
        let displays = Set(brightness.onlineDisplayIDs())
        guard displays != knownDisplayIDs else {
            if !isOn, snapshot != nil, !displays.isEmpty, restore() {
                error = nil
            }
            return
        }
        knownDisplayIDs = displays
        if isClamshell {
            guard !displays.isEmpty else { return }
            if snapshot != nil, !restore() { return }
            now = Date()
            session.displayDidReturn(now: now, delay: delay)
            error = nil
            return
        }
        if isOn, displays.isEmpty, ClamshellState.isClosed() {
            editingDelay = false
            session.enterClamshell()
            return
        }
        if isOn {
            if snapshot != nil, !restore() { return }
            now = Date()
            session.reserve(now: now, delay: delay)
            error = nil
        } else if snapshot != nil, !displays.isEmpty, restore() {
            error = nil
        }
    }

    func shutdown() {
        shuttingDown = true
        timer?.invalidate(); timer = nil
        if !restore() {
            restoreGuard?.handOff()
        }
        restoreGuard = nil; awake.stop(); activity.stop(); keyboard.stop()
    }
}
