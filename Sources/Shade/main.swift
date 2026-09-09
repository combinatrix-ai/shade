import AppKit
import Combine
import SwiftUI

if CommandLine.arguments.contains("--restore-guard") {
    runRestoreGuard()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var panelWindow: NSPanel?
    private var settingsWindow: NSWindow?
    private var demoWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private lazy var model = AppModel(demo: CommandLine.arguments.contains("--demo"))

    func applicationDidFinishLaunching(_: Notification) {
        let id = Bundle.main.bundleIdentifier ?? "app.hmirin.shade"
        if NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != getpid() }) {
            NSApplication.shared.terminate(nil); return
        }
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Shade")
        item.button?.target = self; item.button?.action = #selector(togglePanel)
        item.button?.toolTip = "Shade · オフ"
        model.$session.sink { [weak self] session in
            self?.item.button?.appearsDisabled = !session.isOn
            self?.item.button?.toolTip = session.isOn ? "Shade · スリープ防止中" : "Shade · オフ"
        }.store(in: &subscriptions)
        if CommandLine.arguments.contains("--demo") {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PanelView(model: model, settings: { [weak self] in self?.showSettings() }, quit: { NSApp.terminate(nil) })))
            window.title = "Shade · UIプレビュー"; window.styleMask = [.titled, .closable]; window.center(); window.makeKeyAndOrderFront(nil); demoWindow = window
            NSApp.activate(ignoringOtherApps: true)
        } else {
            showSettings()
        }
    }

    @objc private func togglePanel() {
        if panelWindow?.isVisible == true {
            panelWindow?.orderOut(nil); return
        }
        if panelWindow == nil {
            let panel = NSPanel(contentViewController: NSHostingController(rootView: PanelView(model: model, settings: { [weak self] in self?.showSettings() }, quit: { NSApp.terminate(nil) })))
            panel.title = "Shade"
            panel.styleMask = [.titled, .fullSizeContentView]
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panelWindow = panel
        }
        if let panel = panelWindow, let screen = item.button?.window?.screen ?? NSScreen.main {
            let bounds = screen.visibleFrame
            let iconX = item.button?.window?.frame.midX ?? bounds.maxX - 200
            panel.setFrameOrigin(NSPoint(x: min(max(iconX - panel.frame.width / 2, bounds.minX + 12), bounds.maxX - panel.frame.width - 12), y: bounds.maxY - panel.frame.height - 8))
        }
        panelWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showSettings() {
        panelWindow?.orderOut(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model, showPanel: { [weak self] in self?.settingsWindow?.orderOut(nil); self?.togglePanel() })))
            window.title = "Shade の設定"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_: Notification) {
        model.shutdown()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        togglePanel()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
