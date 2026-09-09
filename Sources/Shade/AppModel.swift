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
        didSet { UserDefaults.standard.set(delay, forKey: "delay"); reserveIfPending() }
    }

    @Published var shortcut: Shortcut {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: "hotkey")
            configureKeyboard()
        }
    }

    @Published var recording = false
    @Published var loginEnabled = false
    private let awake = AwakeHold()
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
        let savedDelay = UserDefaults.standard.double(forKey: "delay")
        delay = [30.0, 60, 180, 300].contains(savedDelay) ? savedDelay : 60
        shortcut = UserDefaults.standard.data(forKey: "hotkey").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .initial
        keyboard.action = { [weak self] in guard self?.recording == false else { return }; self?.shortcutAction() }
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
        case .off: return "いつもの画面に"
        case .pending: let t = session.remaining(now: now); return String(format: "あと %d:%02d で暗転", t / 60, t % 60)
        case .dark: return "画面を暗くしています"
        case .visible: return "画面を表示しています"
        }
    }

    var detail: String {
        switch session.phase {
        case .off: "オンにするとスリープを防ぎ、\n設定した時間のあとに暗転します。"
        case .pending: "内蔵ディスプレイを暗くします。\nアプリの操作はそのまま続きます。"
        case .dark: "ロックせずに、画面の明るさを0に。\nアプリの操作はそのまま続きます。"
        case .visible: "スリープ防止は続いています。\n次の暗転は、キー操作で予約できます。"
        }
    }

    var actionLabel: String {
        switch session.phase { case .off: return "オンにする"; case .pending: return "今すぐ暗くする"; case .dark: return "画面を戻す"; case .visible: return "暗転を予約する" }
    }

    func toggle() {
        isOn ? disable() : enable()
    }

    func enable() {
        error = nil
        configureKeyboard()
        guard demo || keyboard.ready else { error = keyboardIssue ?? "画面を戻すキー操作を設定してください。"; return }
        do {
            if !demo {
                let service = try Brightness()
                let id = try service.internalDisplay()
                _ = try service.get(id)
                brightness = service
                try awake.start()
            }
            enabledAt = Date()
            session.enable(now: Date(), delay: delay)
        } catch { self.error = error.localizedDescription; awake.stop() }
    }

    func disable() {
        guard restore() else { return }
        awake.stop(); enabledAt = nil; session.disable()
    }

    func primaryAction() {
        switch session.phase { case .off: enable(); case .pending: dim(); case .dark: _ = restore(); case .visible: reserve() }
    }

    func shortcutAction() {
        guard isOn else { return }; if isDark {
            _ = restore()
        } else {
            reserve()
        }
    }

    func reserve() {
        session.reserve(now: Date(), delay: delay)
    }

    private func reserveIfPending() {
        if case .pending = session.phase {
            reserve()
        }
    }

    func dim() {
        guard isOn, !isDark else { return }
        error = nil
        if demo {
            session.didDim(); return
        }
        guard keyboard.ready else { error = "復帰キーを利用できないため、暗転を中止しました。"; disable(); return }
        do {
            guard let brightness else { throw ShadeFailure(message: "輝度制御を開始できません。") }
            let id = try brightness.internalDisplay(), original = try brightness.get(id)
            guard original > 0 else { throw ShadeFailure(message: "画面はすでに暗くなっています。明るさを上げてからお試しください。") }
            let guardian = RestoreGuard()
            try guardian.start(display: id, brightness: original)
            snapshot = (id, original); restoreGuard = guardian
            try brightness.set(id, 0)
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
            } catch { self.error = "明るさを戻せませんでした。輝度キーで復帰してください。\n" + error.localizedDescription; return false }
        }
        session.didRestore()
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
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled, !loginEnabled {
                error = "システム設定のログイン項目でShadeを許可してください。"
            }
        } catch { self.error = error.localizedDescription }
    }

    private func tick() {
        now = Date()
        if isOn, !demo, !keyboard.ready || !awake.isRunning || (isDark && restoreGuard?.isRunning != true) {
            error = "復帰キーまたはスリープ防止を利用できなくなったため、終了しました。"
            disable()
            return
        }
        if let enabledAt, now.timeIntervalSince(enabledAt) >= 28790 {
            disable(); return
        }
        if session.isDue(now: now) {
            dim()
        }
    }

    func shutdown() {
        _ = restore(); restoreGuard?.finish(); restoreGuard = nil; awake.stop(); keyboard.stop()
    }
}
