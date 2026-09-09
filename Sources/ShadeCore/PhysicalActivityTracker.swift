import Foundation

/// Tracks hardware input timestamps using a monotonic clock, without input contents.
public struct PhysicalActivityTracker {
    private var lastInput: TimeInterval?
    private var suppressedUntil: TimeInterval = -.infinity

    public init() {}

    public mutating func suppress(until uptime: TimeInterval) {
        suppressedUntil = uptime
    }

    public mutating func sample(idle: TimeInterval, uptime: TimeInterval) -> Bool {
        let input = uptime - idle
        let changed = lastInput.map { input > $0 + 0.05 } ?? false
        lastInput = max(lastInput ?? input, input)
        return changed && input > suppressedUntil
    }
}
