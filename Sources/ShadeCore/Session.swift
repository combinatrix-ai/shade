import Foundation

public enum Phase: Equatable { case off, pending(deadline: Date), dark, visible }

/// State transitions are committed only after the associated system operation succeeds.
public struct Session {
    public private(set) var phase: Phase = .off
    public init() {}
    public var isOn: Bool {
        phase != .off
    }

    public mutating func enable(now: Date, delay: TimeInterval) {
        phase = .pending(deadline: now.addingTimeInterval(delay))
    }

    public mutating func disable() {
        phase = .off
    }

    public mutating func reserve(now: Date, delay: TimeInterval) {
        guard isOn, phase != .dark else { return }
        phase = .pending(deadline: now.addingTimeInterval(delay))
    }

    public func isDue(now: Date) -> Bool {
        if case let .pending(deadline) = phase {
            return now >= deadline
        }
        return false
    }

    public mutating func didDim() {
        if isOn {
            phase = .dark
        }
    }

    public mutating func didRestore() {
        if phase == .dark {
            phase = .visible
        }
    }

    public func remaining(now: Date) -> Int {
        if case let .pending(deadline) = phase {
            return max(0, Int(ceil(deadline.timeIntervalSince(now))))
        }
        return 0
    }
}

/// Requires both physical Shift flags continuously, fires once until either is released.
public struct ShiftHold {
    private var began: TimeInterval?
    private var fired = false
    public init() {}
    public mutating func update(left: Bool, right: Bool, now: TimeInterval) {
        if left, right {
            if began == nil {
                began = now
            }
        } else {
            reset()
        }
    }

    public mutating func poll(now: TimeInterval) -> Bool {
        guard let began, !fired, now - began >= 1 else { return false }
        fired = true
        return true
    }

    public mutating func reset() {
        began = nil; fired = false
    }
}
