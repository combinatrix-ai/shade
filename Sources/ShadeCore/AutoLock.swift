import Foundation

/// All durations are settings measured from inactivity, never a live countdown.
public enum LockTimer: Equatable {
    case unknown, disabled
    case after(Int)

    public static func seconds(_ value: Int?) -> Self {
        guard let value, value >= 0, value <= 31_536_000 else { return .unknown }
        return value == 0 ? .disabled : .after(value)
    }
}

public enum LockRequirement: Equatable {
    case unknown, disabled
    case after(Int)
}

public enum LockRoute: Equatable {
    case unknown, disabled, prevented
    case after(Int)

    public init(timer: LockTimer, prevented: Bool?) {
        if timer == .disabled { self = .disabled; return }
        if prevented == true { self = .prevented; return }
        guard prevented == false else { self = .unknown; return }
        switch timer {
        case .unknown: self = .unknown
        case .disabled: self = .disabled
        case let .after(seconds): self = seconds > 0 && seconds <= 31_536_000 ? .after(seconds) : .unknown
        }
    }
}

public enum AutoLockStatus: Equatable {
    case unknown, disabled, prevented
    case after(Int)

    public static func resolve(display: LockRoute, screensaver: LockRoute, password: LockRequirement) -> Self {
        if password == .disabled { return .disabled }
        let routes = [display, screensaver]
        // Missing data must not silently disappear from min(D, S).
        if routes.contains(.unknown) { return .unknown }
        let durations = routes.compactMap { route -> Int? in
            if case let .after(seconds) = route { return seconds }; return nil
        }
        if let first = durations.min() {
            guard case let .after(grace) = password, grace >= 0, grace <= 31_536_000 else { return .unknown }
            return .after(first + grace)
        }
        if routes.contains(.prevented) { return .prevented }
        return .disabled
    }

    public var label: String {
        switch self {
        case .unknown: return "Normal Auto-Lock"
        case .disabled: return "Auto-Lock Disabled"
        case .prevented: return "Auto-Lock Prevented"
        case let .after(seconds):
            let minutes = seconds / 60, remainder = seconds % 60
            let duration = remainder == 0 ? "\(minutes) min" : minutes == 0 ? "\(remainder) sec" : "\(minutes)m \(remainder)s"
            return "Auto-Lock after " + duration
        }
    }
}
