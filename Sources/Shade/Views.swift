import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: AppModel
    let settings: () -> Void
    let quit: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "circle.lefthalf.filled").foregroundStyle(.green)
                Text("Shade").font(.system(size: 17, weight: .semibold))
                Spacer()
                Toggle("Shade", isOn: Binding(get: { model.isOn }, set: { _ in model.toggle() }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel("Enable Shade")
            }
            HStack(spacing: 6) {
                Circle().fill(model.isOn ? Color(red: 0.26, green: 0.52, blue: 0.43) : .secondary).frame(width: 6, height: 6)
                Text(model.isOn ? "Keeping Mac awake" : "Off").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.top, 8)
            Text(model.title).font(.system(size: 18, weight: .semibold)).padding(.top, 24)
            if let issue = model.error ?? model.keyboardIssue {
                VStack(alignment: .leading, spacing: 6) {
                    Text(issue).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    if model.keyboardIssue != nil {
                        Button("Set Shortcut…", action: settings).font(.system(size: 11))
                    }
                }.padding(.top, 12)
            }
            Button(model.actionLabel) { model.primaryAction() }
                .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity).padding(.top, 18)
            Spacer().frame(height: 22)
            Divider()
            HStack {
                Button("Settings…", action: settings)
                Spacer()
                Button("Quit", action: quit)
            }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 12)
        }.padding(22).frame(width: 320)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    let showPanel: () -> Void
    var checkUpdates: () -> Void = {}
    var showTutorial: () -> Void = {}
    @State private var monitor: Any?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("‹ Back", action: showPanel).buttonStyle(.plain)
                Spacer()
                Text("Settings").fontWeight(.semibold)
                Spacer()
                Color.clear.frame(width: 36, height: 1)
            }.padding(.bottom, 16)
            group {
                row("Dim after") {
                    Picker("Dim after", selection: $model.delay) {
                        Text("30 sec").tag(30.0); Text("1 min").tag(60.0); Text("3 min").tag(180.0); Text("5 min").tag(300.0)
                    }.labelsHidden().frame(width: 100)
                }
                Divider()
                row("Shortcut") {
                    Button(model.recording ? "Press shortcut…" : model.shortcut.label) { beginRecording() }
                        .frame(minWidth: 90).controlSize(.large)
                        .accessibilityLabel("Record shortcut")
                        .help("Restore the display or schedule dimming.")
                }
                if model.recording {
                    HStack {
                        Text("Include ⌘, ⌃ or ⌥").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { endRecording() }
                    }.padding(.bottom, 12)
                }
                Divider()
                row("Wake on touch") {
                    Toggle("Wake on touch", isOn: $model.wakeOnTouch)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .help("Restore on physical trackpad movement, mouse or keyboard input. Resting a finger alone is not detected.")
                }
                Divider()
                row("Launch at login") {
                    Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            if let issue = model.keyboardIssue {
                VStack(alignment: .leading, spacing: 10) {
                    Label(issue, systemImage: "keyboard").font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)

                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)).padding(.bottom, 22)
            }
            if let error = model.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Tutorial", action: showTutorial)
                Spacer()
                Button("Check for Updates…", action: checkUpdates).disabled(model.demo)
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 16)
            Text("Version " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")).font(.caption2).foregroundStyle(.secondary).padding(.top, 10)
            if model.demo {
                Text("Preview").font(.caption).foregroundStyle(.secondary)
            }
        }.font(.system(size: 13)).padding(22).frame(width: 320)
            .background(Color(nsColor: .windowBackgroundColor))
            .onDisappear { endRecording() }
    }

    private func group(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0, content: content).padding(.horizontal, 13).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.gray.opacity(0.18)))
    }

    private func row(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack { Text(title); Spacer(minLength: 16); content() }.frame(minHeight: 48)
    }

    private func beginRecording() {
        endRecording()
        model.recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                endRecording(); return nil
            }
            guard let shortcut = Shortcut.capture(event) else { return nil }
            model.shortcut = shortcut
            endRecording()
            return nil
        }
    }

    private func endRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }; monitor = nil; model.recording = false
    }
}
