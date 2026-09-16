import Foundation
import IOKit.pwr_mgt
import IOKit.ps
import ShadeCore

struct AutoLockSnapshot {
    var display: LockTimer = .unknown
    var screensaver: LockTimer = .unknown
    var password: LockRequirement = .unknown
    var displayPrevented: Bool?
    var screensaverPrevented: Bool?

    var status: AutoLockStatus {
        .resolve(display: LockRoute(timer: display, prevented: displayPrevented),
                 screensaver: LockRoute(timer: screensaver, prevented: screensaverPrevented), password: password)
    }
}

/// Read-only, executed off the UI thread. No raw settings or process lists are persisted.
enum AutoLockMonitor {
    static func read() -> AutoLockSnapshot {
        var result = AutoLockSnapshot()
        result.display = displayTimer()
        let domain = "com.apple.screensaver" as CFString
        // AppValue resolves managed preferences before the user's ByHost value.
        CFPreferencesAppSynchronize(domain)
        result.screensaver = .seconds(integer(CFPreferencesCopyAppValue("idleTime" as CFString, domain)))
        result.password = passwordRequirement()
        var assertions: Unmanaged<CFDictionary>?
        if IOPMCopyAssertionsByProcess(&assertions) == kIOReturnSuccess,
           let entries = assertions?.takeRetainedValue() as? [NSNumber: [[String: Any]]] {
            let holds = prevention(entries.values.flatMap { $0 })
            result.displayPrevented = holds.display
            result.screensaverPrevented = holds.screensaver
        }
        return result
    }

    static func prevention(_ assertions: [[String: Any]]) -> (display: Bool, screensaver: Bool?) {
        let active = assertions.filter { ($0[kIOPMAssertionLevelKey] as? NSNumber)?.intValue == kIOPMAssertionLevelOn }
        let displayHold = active.contains { ($0[kIOPMAssertionTypeKey] as? String) == kIOPMAssertionTypePreventUserIdleDisplaySleep }
        // Ordinary WindowServer activity is not an app lock hold. Only recognize
        // explicit sustained caffeinate -u holds (the mechanism Shade uses).
        let userHold = active.contains {
            ($0[kIOPMAssertionTypeKey] as? String) == "UserIsActive" &&
            ($0[kIOPMAssertionNameKey] as? String) == "caffeinate command-line tool" &&
            (($0[kIOPMAssertionTimeoutKey] as? NSNumber)?.doubleValue ?? 0) > 5
        }
        let otherUserHold = active.contains {
            ($0[kIOPMAssertionTypeKey] as? String) == "UserIsActive" &&
            !(($0[kIOPMAssertionNameKey] as? String) ?? "").hasPrefix("com.apple.iohideventsystem.queue.tickle") &&
            ($0[kIOPMAssertionNameKey] as? String) != "caffeinate command-line tool"
        }
        // A display-only hold does not establish the screen saver's behavior.
        return (displayHold || userHold || otherUserHold, userHold ? true : (displayHold || otherUserHold) ? nil : false)
    }

    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double >= 0, double <= 31_536_000, double.rounded() == double else { return nil }
        return Int(double)
    }

    private static func displayTimer() -> LockTimer {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let supply = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String?,
              [kIOPMACPowerKey, kIOPMBatteryPowerKey].contains(supply),
              let data = try? Data(contentsOf: URL(fileURLWithPath: "/Library/Preferences/com.apple.PowerManagement.plist")),
              let settings = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let profile = settings[supply] as? [String: Any],
              let minutes = integer(profile["Display Sleep Timer"]), minutes <= 525_600 else { return .unknown }
        return .seconds(minutes * 60)
    }

    static func parsePasswordStatus(_ text: String) -> LockRequirement {
        // sysadminctl reports the effective setting (including managed settings).
        if text.contains("screenLock delay is immediate") { return .after(0) }
        if text.contains("screenLock is off") { return .disabled }
        guard let regex = try? NSRegularExpression(pattern: #"screenLock delay is ([0-9]+) seconds(?:\s|$)"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text), let seconds = Int(text[range]), seconds <= 31_536_000 else { return .unknown }
        return .after(seconds)
    }

    private static func passwordRequirement() -> LockRequirement {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysadminctl")
        process.arguments = ["-screenLock", "status"]
        process.environment = ["LC_ALL": "C", "LANG": "C", "PATH": "/usr/bin:/usr/sbin:/bin:/sbin"]
        process.standardOutput = output; process.standardError = output
        do { try process.run() } catch { return .unknown }
        // This status-only command produces a single short line. Bound its lifetime.
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        guard !process.isRunning else { process.terminate(); return .unknown }
        guard process.terminationStatus == 0 else { return .unknown }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return parsePasswordStatus(String(decoding: data, as: UTF8.self))
    }
}
