import SwiftUI

struct PanelRoot: View {
    @ObservedObject var model: AppModel
    let checkUpdates: () -> Void
    @State private var page: Page
    @State private var hideTutorial = false
    enum Page { case main, settings, tutorial }

    init(model: AppModel, checkUpdates: @escaping () -> Void) {
        self.model = model
        self.checkUpdates = checkUpdates
        _page = State(initialValue: model.demo || !UserDefaults.standard.bool(forKey: "hideTutorial") ? .tutorial : .main)
    }

    var body: some View {
        Group {
            switch page {
            case .main:
                PanelView(model: model, settings: { page = .settings }, quit: { NSApp.terminate(nil) })
            case .settings:
                SettingsView(model: model, showPanel: { page = .main }, checkUpdates: checkUpdates, showTutorial: { page = .tutorial })
            case .tutorial:
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.lefthalf.filled").foregroundStyle(.green)
                        Text("Shade").fontWeight(.semibold)
                    }.font(.system(size: 17)).padding(.bottom, 26)
                    Text("A dark display.\nA working Mac.").font(.system(size: 25, weight: .semibold)).tracking(-0.7)
                    Text("Keep Computer Use running while your built-in display is dimmed.")
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4).padding(.top, 14).padding(.bottom, 24)
                    Divider()
                    HStack(spacing: 12) {
                        KeyboardIllustration()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Need your screen back?").fontWeight(.semibold).foregroundStyle(Color(red: 0.69, green: 0.27, blue: 0.24))
                            Text("Press the brightness-up key.").foregroundStyle(.secondary)
                            Text("Or press " + model.shortcut.label).foregroundStyle(.secondary)
                        }.font(.system(size: 11))
                    }.padding(.vertical, 20)
                    Toggle("Don’t show on startup", isOn: $hideTutorial).toggleStyle(.checkbox).font(.system(size: 12))
                    Button("Got it — Start using Shade") {
                        if !model.demo {
                            UserDefaults.standard.set(hideTutorial, forKey: "hideTutorial")
                        }
                        page = .main
                    }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity).padding(.top, 14)
                    Text("Dimming doesn’t lock your Mac.\nShade is a privacy band-aid, not security.")
                        .font(.system(size: 11)).foregroundStyle(Color(red: 0.69, green: 0.27, blue: 0.24)).lineSpacing(4).padding(.top, 22)
                }.padding(22).frame(width: 320)
            }
        }.fixedSize(horizontal: true, vertical: true).tint(Color(red: 0.39, green: 0.53, blue: 0.46))
    }
}

private struct KeyboardIllustration: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(white: 0.74)
            key("", "F1").offset(x: -35, y: 8)
            key("sun.max.fill", "F2").offset(x: 21, y: 8)
            key("", "F3").offset(x: 77, y: 8)
            key("", "1").offset(x: -15, y: 65)
            key("", "2").offset(x: 41, y: 65)
        }.frame(width: 92, height: 86).clipShape(RoundedRectangle(cornerRadius: 9))
            .accessibilityElement(children: .ignore).accessibilityLabel("Mac keyboard: brightness-up F2 key")
    }

    private func key(_ symbol: String, _ label: String) -> some View {
        VStack(spacing: 5) {
            if !symbol.isEmpty {
                Image(systemName: symbol).font(.system(size: 21))
            }
            Text(label).font(.system(size: 9))
        }.frame(width: 50, height: 51).foregroundStyle(.white)
            .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.8)))
    }
}
