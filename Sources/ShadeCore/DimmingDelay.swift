import Foundation

public enum DimmingDelay {
    public static let minutes = 1...60

    /// Settings are stored in seconds, but the UI accepts whole minutes only.
    public static func restoredSeconds(_ saved: TimeInterval) -> TimeInterval {
        guard saved.isFinite, (60...3600).contains(saved), saved.truncatingRemainder(dividingBy: 60) == 0 else {
            return 60
        }
        return saved
    }
}
