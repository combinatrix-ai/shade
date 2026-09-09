import Foundation

public enum ActivityResponse { case none, postpone, restore }

public enum Phase: Equatable { case off, pending(deadline: Date), dark }

/// State transitions are committed only after the associated system operation succeeds.
public struct Session {
    public private(set) var phase: Phase = .off
    private var countdownDuration: TimeInterval = 0
    public init() {}
    public var isOn: Bool {
        phase != .off
    }

    public mutating func enable(now: Date, delay: TimeInterval) {
        countdownDuration = delay
        phase = .pending(deadline: now.addingTimeInterval(delay))
    }

    public mutating func disable() {
        phase = .off
    }

    public mutating func reserve(now: Date, delay: TimeInterval) {
        guard isOn, phase != .dark else { return }
        countdownDuration = delay
        phase = .pending(deadline: now.addingTimeInterval(delay))
    }

    public func activityResponse(detected: Bool, wakeOnTouch: Bool) -> ActivityResponse {
        guard detected else { return .none }
        switch phase {
        case .off: return .none
        case .pending: return .postpone
        case .dark: return wakeOnTouch ? .restore : .none
        }
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

    public mutating func didRestore(now: Date, delay: TimeInterval) {
        if phase == .dark {
            countdownDuration = delay
            phase = .pending(deadline: now.addingTimeInterval(delay))
        }
    }

    public func remaining(now: Date) -> Int {
        if case let .pending(deadline) = phase {
            return max(0, Int(ceil(min(countdownDuration, deadline.timeIntervalSince(now)))))
        }
        return 0
    }
}
