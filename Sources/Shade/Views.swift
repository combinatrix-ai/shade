import AppKit
import SwiftUI

private enum ShadeStyle {
    static let green = Color(red: 0.28, green: 0.41, blue: 0.34)
    static let amber = Color(red: 0.58, green: 0.44, blue: 0.19)
    static let red = Color(red: 0.69, green: 0.27, blue: 0.24)
}

struct ShadeActionStyle: ButtonStyle {
    var neutral = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(maxWidth: .infinity).padding(.vertical, 9)
            .foregroundStyle(neutral ? Color.primary : .white)
            .background(neutral ? Color.primary.opacity(0.07) : ShadeStyle.green,
                        in: RoundedRectangle(cornerRadius: 8))
            .opacity(!enabled ? 0.35 : configuration.isPressed ? 0.75 : 1)
    }
}

struct PanelView: View {
    @ObservedObject var model: AppModel
    let settings: () -> Void
    let quit: () -> Void

    private var status: String {
        model.isOn ? "Keeping Mac awake" : model.waitingForPower ? "Paused" : model.blockedByPower ? "On battery" : ""
    }
    private var stateColor: Color {
        model.waitingForPower || model.blockedByPower ? ShadeStyle.amber : model.isOn ? ShadeStyle.green : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "circle.lefthalf.filled").foregroundStyle(ShadeStyle.green)
                Text("Shade").font(.system(size: 17, weight: .semibold))
                Spacer()
                Toggle("Shade", isOn: Binding(get: { model.isOn || model.waitingForPower }, set: { _ in model.toggle() }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .tint(model.waitingForPower ? ShadeStyle.amber : ShadeStyle.green)
                    .accessibilityLabel("Enable Shade").disabled(model.enableControlDisabled)
            }
            HStack(spacing: 7) {
                Text(model.isOn || model.waitingForPower ? "ON" : "OFF")
                    .font(.system(size: 9, weight: .bold)).tracking(0.8)
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .foregroundStyle(model.isOn ? .white : stateColor)
                    .background(model.isOn ? ShadeStyle.green : stateColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
                Text(status).font(.system(size: 11)).foregroundStyle(stateColor)
            }.padding(.top, 18)
            Text(model.title).font(.system(size: 21, weight: .semibold)).tracking(-0.6)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 14)
            if !model.isOn && !model.waitingForPower && !model.blockedByPower {
                Text("Auto-dim after " + model.delayLabel).font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
            }
            if model.isOn && !model.isDark {
                ProgressView(value: Double(model.session.remaining(now: model.now)), total: model.delay)
                    .tint(ShadeStyle.green).padding(.top, 18)
            }
            if model.waitingForPower {
                notice(color: ShadeStyle.amber) {
                    Label("Resumes when reconnected.", systemImage: "battery.100")
                }
            } else if model.blockedByPower {
                notice(color: ShadeStyle.amber) {
                    Label("Only on power adapter", systemImage: "battery.100").fontWeight(.medium)
                    Button("Allow on Battery") { model.allowOnBattery() }.controlSize(.small)
                }
            }
            if let issue = model.error ?? model.keyboardIssue {
                notice(color: ShadeStyle.red) {
                    Text(issue).fixedSize(horizontal: false, vertical: true)
                    if model.needsBrightnessRecovery {
                        Button("Retry Restore") { model.retryRestore() }
                    } else if model.keyboardIssue != nil {
                        Button("Set Shortcut…", action: settings)
                    }
                }
            }
            Button(model.actionLabel) { model.primaryAction() }
                .buttonStyle(ShadeActionStyle(neutral: model.waitingForPower))
                .disabled(model.enableControlDisabled).padding(.top, 18)
            if model.isDark {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Restore: brightness-up or " + model.shortcut.label)
                    if model.wakeOnTouch { Text("Or move the trackpad.") }
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 10)
            } else if model.waitingForPower {
                Text("Turn Off cancels auto-resume.").font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 10)
            }
            Divider().padding(.top, 20)
            HStack {
                Button("Settings ›", action: settings)
                Spacer()
                Button("Quit", action: quit)
            }.buttonStyle(.plain).font(.system(size: 12)).padding(.top, 12)
        }.padding(22).frame(width: 320)
    }

    private func notice<Content: View>(color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .font(.system(size: 11)).foregroundStyle(color).padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)).padding(.top, 14)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    let showPanel: () -> Void
    var checkUpdates: () -> Void = {}
    var showTutorial: () -> Void = {}
    @State private var monitor: Any?
    @State private var recordingError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("‹ Back", action: showPanel).buttonStyle(.plain)
                Spacer()
                Text("Settings").fontWeight(.semibold)
                Spacer()
                Color.clear.frame(width: 36, height: 1)
            }.padding(.bottom, 16)
            VStack(alignment: .leading, spacing: 0) {
                row("Dim after") {
                    Picker("Dim after", selection: $model.delay) {
                        Text("30 sec").tag(30.0); Text("1 min").tag(60.0); Text("3 min").tag(180.0); Text("5 min").tag(300.0)
                    }.labelsHidden().frame(width: 90)
                }
                Divider()
                row("Shortcut") {
                    Button(model.recording ? "Press keys…" : model.shortcut.label) { beginRecording() }
                        .frame(minWidth: 80).controlSize(.large)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(model.recording ? (recordingError == nil ? ShadeStyle.green : ShadeStyle.red) : .clear))
                        .accessibilityLabel("Record shortcut")
                }
                if model.recording {
                    HStack {
                        Text("Include ⌘, ⌃ or ⌥").font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { endRecording() }.controlSize(.small)
                    }.padding(.bottom, 10)
                }
                if let issue = recordingError ?? model.keyboardIssue {
                    Text(issue).font(.system(size: 11)).foregroundStyle(ShadeStyle.red)
                        .fixedSize(horizontal: false, vertical: true).padding(.bottom, 12)
                }
                Divider()
                row("Wake on touch", detail: "Move the trackpad or type to restore.") {
                    Toggle("Wake on touch", isOn: $model.wakeOnTouch).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .help("Physical movement or typing restores the display. A resting finger alone is not detected.")
                }
                Divider()
                row("Only on power adapter", detail: "Pause on battery. Resume on power.", badge: model.blockedByPower ? "ON BATTERY" : nil) {
                    Toggle("Only on power adapter", isOn: $model.onlyOnPowerAdapter).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider()
                row("Launch at login") {
                    Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }.padding(.horizontal, 12)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.gray.opacity(0.16)))
            if let error = model.error, error != model.keyboardIssue {
                Text(error).font(.system(size: 11)).foregroundStyle(ShadeStyle.red).padding(.top, 12)
            }
            HStack {
                Button("Tutorial", action: showTutorial)
                Spacer()
                Button("Check for Updates…", action: checkUpdates).disabled(model.demo)
            }.buttonStyle(.plain).font(.system(size: 11)).padding(.top, 16)
            Text("Version " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"))
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 10)
        }.font(.system(size: 13)).padding(22).frame(width: 320)
            .onDisappear { endRecording() }
    }

    private func row<Content: View>(_ title: String, detail: String? = nil, badge: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                if let badge {
                    Text(badge).font(.system(size: 9, weight: .semibold)).foregroundStyle(ShadeStyle.amber)
                }
                if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
            content()
        }.padding(.vertical, 12).frame(minHeight: 46)
    }

    private func beginRecording() {
        endRecording()
        model.recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { endRecording(); return nil }
            guard let shortcut = Shortcut.capture(event) else {
                recordingError = "Add ⌘, ⌃ or ⌥ to the combination."
                return nil
            }
            if let issue = model.captureShortcut(shortcut) {
                recordingError = issue
            } else { endRecording() }
            return nil
        }
    }

    private func endRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; model.recording = false; recordingError = nil
    }
}
