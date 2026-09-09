import AppKit
import Carbon
import ShadeCore

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt32
    var label: String
    static func capture(_ event: NSEvent) -> Shortcut? {
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard f.contains(.command) || f.contains(.control) || f.contains(.option),
              let text = event.charactersIgnoringModifiers, !text.isEmpty else { return nil }
        var mods: UInt32 = 0
        if f.contains(.command) {
            mods |= UInt32(cmdKey)
        }
        if f.contains(.control) {
            mods |= UInt32(controlKey)
        }
        if f.contains(.option) {
            mods |= UInt32(optionKey)
        }
        if f.contains(.shift) {
            mods |= UInt32(shiftKey)
        }
        let label = (f.contains(.control) ? "⌃" : "") + (f.contains(.option) ? "⌥" : "") + (f.contains(.shift) ? "⇧" : "") + (f.contains(.command) ? "⌘" : "") + text.uppercased()
        return Shortcut(keyCode: event.keyCode, modifiers: mods, label: label)
    }
}

final class KeyboardListener {
    var action: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var hold = ShiftHold()
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var ready: Bool {
        tap != nil || hotKey != nil
    }

    func configure(custom: Shortcut?) -> String? {
        stop()
        if let custom {
            return register(custom)
        }
        guard CGPreflightListenEventAccess() else { return "左右Shiftの検出には「入力監視」の許可が必要です。" }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let listener = Unmanaged<KeyboardListener>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                listener.hold.reset()
                if let tap = listener.tap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            } else {
                let flags = event.flags.rawValue
                listener.hold.update(left: flags & 0x2 != 0, right: flags & 0x4 != 0, now: ProcessInfo.processInfo.systemUptime)
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return "キーボードの監視を開始できません。入力監視の許可を確認してください。" }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            if hold.poll(now: ProcessInfo.processInfo.systemUptime) {
                action?()
            }
        }
        return nil
    }

    private func register(_ shortcut: Shortcut) -> String? {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<KeyboardListener>.fromOpaque(context).takeUnretainedValue().action?()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { return "ショートカットの検出を開始できません。" }
        let id = EventHotKeyID(signature: 0x5348_4445, id: 1)
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else { stop(); return "このショートカットは登録できません。別の組み合わせを選んでください。" }
        return nil
    }

    func stop() {
        timer?.invalidate(); timer = nil; hold.reset()
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        source = nil; tap = nil
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }; hotKey = nil
        if let handler {
            RemoveEventHandler(handler)
        }; handler = nil
    }

    deinit { stop() }
}
