import Foundation
import IOKit
import ShadeCore

/// Reads only elapsed hardware idle time; never receives key codes or pointer positions.
final class PhysicalActivity {
    private var service: io_service_t = 0
    private var tracker = PhysicalActivityTracker()

    func start() throws {
        stop()
        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard sample() != nil else {
            stop()
            throw ShadeFailure(message: "Hardware activity detection is unavailable.")
        }
    }

    /// nil means detection failed. Do not dim when the idle signal is unavailable.
    func sample() -> Bool? {
        guard service != 0,
              let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber else { return nil }
        let idle = value.doubleValue / 1_000_000_000
        guard idle.isFinite, idle >= 0 else { return nil }
        return tracker.sample(idle: idle, uptime: ProcessInfo.processInfo.systemUptime)
    }

    func suppressDimmingGesture() {
        tracker.suppress(until: ProcessInfo.processInfo.systemUptime + 2)
    }

    func stop() {
        if service != 0 {
            IOObjectRelease(service)
        }
        service = 0
        tracker = PhysicalActivityTracker()
    }

    deinit { stop() }
}
