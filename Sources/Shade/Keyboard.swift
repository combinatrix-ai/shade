import AppKit
import Carbon

struct Shortcut: Codable, Equatable {
    static let initial = Shortcut(keyCode: UInt16(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey | cmdKey), label: "⌃⌥⌘D")
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
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var ready: Bool {
        hotKey != nil
    }

    func configure(shortcut: Shortcut) -> String? {
        stop()
        return register(shortcut)
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
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }; hotKey = nil
        if let handler {
            RemoveEventHandler(handler)
        }; handler = nil
    }

    deinit { stop() }
}
