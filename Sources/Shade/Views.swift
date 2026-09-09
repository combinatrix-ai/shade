import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: AppModel
    let settings: () -> Void
    let quit: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Shade").font(.system(size: 17, weight: .semibold))
                Spacer()
                Toggle("Shade", isOn: Binding(get: { model.isOn }, set: { _ in model.toggle() }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel("Shadeをオンにする")
            }
            HStack(spacing: 6) {
                Circle().fill(model.isOn ? Color(red: 0.26, green: 0.52, blue: 0.43) : .secondary).frame(width: 6, height: 6)
                Text(model.isOn ? "スリープ防止中" : "オフ · 通常のスリープ設定").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.top, 8)
            ZStack {
                Image(systemName: "laptopcomputer").font(.system(size: 83, weight: .ultraLight)).foregroundStyle(model.isDark ? Color.primary : Color.gray)
                if !model.isDark {
                    Image(systemName: "circle.lefthalf.filled").font(.system(size: 23)).foregroundStyle(Color(red: 0.45, green: 0.60, blue: 0.54)).offset(y: -5)
                }
            }.frame(maxWidth: .infinity).frame(height: 132)
            Text(model.title).font(.system(size: 18, weight: .semibold))
            Text(model.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).padding(.top, 7).fixedSize(horizontal: false, vertical: true)
            if let issue = model.error ?? model.keyboardIssue {
                VStack(alignment: .leading, spacing: 6) {
                    Text(issue).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    if model.keyboardIssue != nil {
                        Button("キー操作を設定…", action: settings).font(.system(size: 11))
                    }
                }.padding(.top, 12)
            }
            Button(model.actionLabel) { model.primaryAction() }
                .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity).padding(.top, 18)
            HStack(spacing: 4) {
                Text(model.keyLabel)
                Text(model.isDark ? "で画面を戻す" : "で暗転を予約")
            }.font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 18)
            Divider()
            HStack {
                Button("設定…", action: settings)
                Spacer()
                Button("Shadeを終了", action: quit)
            }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 12)
        }.padding(20).frame(width: 336)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    let showPanel: () -> Void
    @State private var monitor: Any?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("画面")
            group {
                row("暗転までの時間") {
                    Picker("暗転までの時間", selection: $model.delay) {
                        Text("30秒").tag(30.0); Text("1分").tag(60.0); Text("3分").tag(180.0); Text("5分").tag(300.0)
                    }.labelsHidden().frame(width: 85)
                }
                Divider()
                row("対象ディスプレイ") { Text("内蔵ディスプレイ").foregroundStyle(.secondary) }
            }
            help("オンにしたとき、またはキー操作で予約したときから数えます。")
            section("キーボード")
            group {
                row("画面を戻す／暗転を予約") {
                    Button(model.recording ? "キーを押してください…" : model.shortcut.label) { beginRecording() }
                        .frame(minWidth: 170).controlSize(.large)
                        .accessibilityLabel("ショートカットを記録")
                }
                if model.recording {
                    HStack { Text("⌘・⌃・⌥を含む組み合わせを入力").font(.caption).foregroundStyle(.secondary); Spacer(); Button("キャンセル") { endRecording() } }.padding(.bottom, 12)
                }
            }
            help("暗転中はすぐに表示。表示中は暗転を予約します。\nマウスを動かしたり、通常のキー入力をしても画面は戻りません。")
            if let issue = model.keyboardIssue {
                VStack(alignment: .leading, spacing: 10) {
                    Label(issue, systemImage: "keyboard").font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)

                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)).padding(.bottom, 22)
            }
            section("起動と終了")
            group {
                row("ログイン時にShadeを起動") {
                    Toggle("ログイン時にShadeを起動", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            help("起動時はオフ。終了すると元の明るさに戻り、通常のスリープ・ロック設定が適用されます。\n連続使用は最大8時間で終了します。")
            if let error = model.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack { Spacer(); Button("メニューパネルを開く", action: showPanel).font(.system(size: 11)) }
            if model.demo {
                Text("UIプレビュー · Macの設定は変更しません").font(.caption).foregroundStyle(.secondary)
            }
        }.font(.system(size: 13)).padding(28).frame(width: 554)
            .background(Color(nsColor: .windowBackgroundColor))
            .onDisappear { endRecording() }
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold)).padding(.bottom, 9)
    }

    private func help(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true).padding(.top, 8).padding(.bottom, 22)
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
