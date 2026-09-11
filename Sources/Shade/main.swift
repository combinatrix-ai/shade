import AppKit
import Combine
import Sparkle
import SwiftUI

signal(SIGPIPE, SIG_IGN)

if CommandLine.arguments.contains("--restore-guard") {
    runRestoreGuard()
}

final class MenuPanel: NSPanel {
    var cancel: (() -> Void)?
    override var canBecomeKey: Bool {
        true
    }

    override func cancelOperation(_ sender: Any?) {
        cancel?()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var item: NSStatusItem!
    private var panelWindow: NSPanel?
    private var pendingIconClick: DispatchWorkItem?
    private var outsideMonitor: Any?
    private var escapeMonitor: Any?
    private var updater: SPUStandardUpdaterController?
    private var demoWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private lazy var model = AppModel(demo: CommandLine.arguments.contains("--demo"))

    func applicationDidFinishLaunching(_: Notification) {
        let id = Bundle.main.bundleIdentifier ?? "ai.combinatrix.shade"
        if NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != getpid() }) {
            NSApplication.shared.terminate(nil); return
        }
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Shade")
        item.button?.target = self; item.button?.action = #selector(handleIconClick)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = "Shade · Off"
        model.$session.combineLatest(model.$waitingForPower, model.$adapterConnected, model.$onlyOnPowerAdapter)
            .sink { [weak self] session, waiting, connected, adapterOnly in
                self?.item.button?.appearsDisabled = !session.isOn
                let status = session.isOn ? "Keeping Mac awake" : waiting ? "Paused, waiting for power" : adapterOnly && !connected ? "Needs a power adapter" : "Off"
                self?.item.button?.toolTip = "Shade · " + status
            }.store(in: &subscriptions)
        if !model.demo, Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil {
            updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }
        if CommandLine.arguments.contains("--demo") {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PanelRoot(model: model, checkUpdates: { [weak self] in self?.updater?.checkForUpdates(nil) })))
            window.title = "Shade · Preview"; window.styleMask = [.titled, .closable]; window.center(); window.makeKeyAndOrderFront(nil); demoWindow = window
            NSApp.activate(ignoringOtherApps: true)
        } else {
            togglePanel()
        }
    }

    @objc private func handleIconClick() {
        pendingIconClick?.cancel()
        pendingIconClick = nil
        guard let event = NSApp.currentEvent else { togglePanel(); return }
        if event.type == .rightMouseUp || event.clickCount == 2 {
            hidePanel()
            model.toggle()
            if model.enableControlDisabled { togglePanel() }
            return
        }
        guard event.clickCount <= 1 else { return }
        // Defer the single click so a double click never briefly opens the panel.
        let action = DispatchWorkItem { [weak self] in
            self?.pendingIconClick = nil
            self?.togglePanel()
        }
        pendingIconClick = action
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: action)
    }

    @objc private func togglePanel() {
        if panelWindow?.isVisible == true {
            hidePanel(); return
        }
        if panelWindow == nil {
            let panel = MenuPanel(contentViewController: NSHostingController(rootView: PanelRoot(model: model, checkUpdates: { [weak self] in self?.updater?.checkForUpdates(nil) })))
            panel.cancel = { [weak self] in self?.cancelPanel() }
            panel.title = "Shade"
            panel.styleMask = [.titled, .fullSizeContentView]
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = true
            panel.delegate = self
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panelWindow = panel
        }
        positionPanel()
        if outsideMonitor == nil {
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.hidePanel() }
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53, self?.panelWindow?.isVisible == true, self?.model.recording != true {
                    self?.cancelPanel()
                    return nil
                }
                return event
            }
        }
        panelWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func positionPanel() {
        guard let panel = panelWindow, let screen = item.button?.window?.screen ?? NSScreen.main else { return }
        let bounds = screen.visibleFrame
        let iconX = item.button?.window?.frame.midX ?? bounds.maxX - 200
        panel.setFrameOrigin(NSPoint(x: min(max(iconX - panel.frame.width / 2, bounds.minX + 12), bounds.maxX - panel.frame.width - 12), y: bounds.maxY - panel.frame.height - 8))
    }

    func windowDidResize(_ notification: Notification) {
        if notification.object as? NSWindow === panelWindow { positionPanel() }
    }

    private func cancelPanel() {
        guard !model.recording else { return }
        if model.editingDelay {
            model.editingDelay = false
        } else {
            hidePanel()
        }
    }

    private func hidePanel() {
        model.editingDelay = false
        panelWindow?.orderOut(nil)
        if let outsideMonitor {
            NSEvent.removeMonitor(outsideMonitor)
        }; outsideMonitor = nil
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }; escapeMonitor = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === panelWindow {
            hidePanel()
        }
    }

    func applicationDidResignActive(_: Notification) {
        hidePanel()
    }

    func applicationWillTerminate(_: Notification) {
        pendingIconClick?.cancel()
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
