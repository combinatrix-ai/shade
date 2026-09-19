import AppKit
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

struct ShadeFailure: LocalizedError {
    let message: String
    var errorDescription: String? {
        message
    }
}

/// DisplayServices is a private macOS framework. Fail closed if the API disappears.
final class Brightness {
    typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias Set = @convention(c) (UInt32, Float) -> Int32
    private let handle: UnsafeMutableRawPointer
    private let getValue: Get
    private let setValue: Set
    init() throws {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let getter = dlsym(handle, "DisplayServicesGetBrightness"),
              let setter = dlsym(handle, "DisplayServicesSetBrightness")
        else {
            throw ShadeFailure(message: "Brightness control is unavailable on this Mac.")
        }
        self.handle = handle
        getValue = unsafeBitCast(getter, to: Get.self)
        setValue = unsafeBitCast(setter, to: Set.self)
    }

    deinit { dlclose(handle) }
    func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    func snapshots() throws -> [DisplaySnapshot] {
        try onlineDisplayIDs().map { id in
            if let value = try? get(id), (try? set(id, value)) != nil {
                return DisplaySnapshot(id: id, method: .brightness(value))
            }
            if let gamma = try? GammaSnapshot.capture(display: id),
               (try? gamma.restore(display: id)) != nil
            {
                return DisplaySnapshot(id: id, method: .gamma(gamma))
            }
            throw ShadeFailure(message: "Cannot dim every online display. Display \(id) does not expose brightness or gamma control.")
        }
    }

    func dim(_ snapshots: [DisplaySnapshot]) throws {
        for snapshot in snapshots {
            let display = try resolve(snapshot)
            switch snapshot.method {
            case .brightness:
                try set(display, 0)
            case .gamma:
                try GammaSnapshot.black(display: display)
            }
        }
    }

    func restore(_ snapshots: [DisplaySnapshot]) throws {
        var failure: Error?
        for snapshot in snapshots {
            do {
                let display = try resolve(snapshot)
                switch snapshot.method {
                case let .brightness(value): try set(display, value)
                case let .gamma(gamma): try gamma.restore(display: display)
                }
            } catch {
                failure = error
            }
        }
        if let failure {
            throw ShadeFailure(message: "Could not restore every display. \(failure.localizedDescription)")
        }
    }

    func hasHardwareBrightnessRestored(_ snapshots: [DisplaySnapshot]) -> Bool {
        snapshots.contains { snapshot in
            guard case .brightness = snapshot.method,
                  let display = try? resolve(snapshot),
                  let value = try? get(display) else { return false }
            return value > 0
        }
    }

    private func resolve(_ snapshot: DisplaySnapshot) throws -> CGDirectDisplayID {
        let displays = onlineDisplayIDs()
        if displays.contains(snapshot.id), snapshot.identity.matches(display: snapshot.id) {
            return snapshot.id
        }
        if let display = displays.first(where: { snapshot.identity.matches(display: $0) }) {
            return display
        }
        throw ShadeFailure(message: "A dimmed display is offline. It will restore when it returns.")
    }

    func get(_ id: CGDirectDisplayID) throws -> Float {
        var value: Float = 0
        guard getValue(id, &value) == 0, value.isFinite, (0 ... 1).contains(value) else {
            throw ShadeFailure(message: "Cannot read brightness. Display will stay on.")
        }
        return value
    }

    func set(_ id: CGDirectDisplayID, _ value: Float) throws {
        guard setValue(id, value) == 0 else { throw ShadeFailure(message: "Could not change display brightness.") }
    }
}

fileprivate struct DisplayIdentity {
    let builtin: Bool
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32

    init(display: CGDirectDisplayID) {
        builtin = CGDisplayIsBuiltin(display) != 0
        vendor = CGDisplayVendorNumber(display)
        model = CGDisplayModelNumber(display)
        serial = CGDisplaySerialNumber(display)
    }

    func matches(display: CGDirectDisplayID) -> Bool {
        let other = DisplayIdentity(display: display)
        return builtin == other.builtin && vendor == other.vendor && model == other.model && serial == other.serial
    }
}

enum DisplayMethodKind: String {
    case brightness = "b"
    case gamma = "g"
}

enum DisplayDimmingMethod {
    case brightness(Float)
    case gamma(GammaSnapshot)

    var kind: DisplayMethodKind {
        switch self {
        case .brightness: return .brightness
        case .gamma: return .gamma
        }
    }

    func guardArgument(display: CGDirectDisplayID) -> String {
        switch self {
        case let .brightness(value): return "\(display):\(kind.rawValue):\(value)"
        case .gamma: return "\(display):\(kind.rawValue)"
        }
    }
}

struct DisplaySnapshot {
    let id: CGDirectDisplayID
    fileprivate let identity: DisplayIdentity
    let method: DisplayDimmingMethod

    init(id: CGDirectDisplayID, method: DisplayDimmingMethod) {
        self.id = id
        identity = DisplayIdentity(display: id)
        self.method = method
    }
}

struct GammaSnapshot {
    let red: [CGGammaValue]
    let green: [CGGammaValue]
    let blue: [CGGammaValue]

    static func capture(display: CGDirectDisplayID) throws -> GammaSnapshot {
        let capacity = CGDisplayGammaTableCapacity(display)
        guard capacity > 0, capacity <= 16_384 else {
            throw ShadeFailure(message: "Display gamma control is unavailable.")
        }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red
        var blue = red
        var count: UInt32 = 0
        let result = red.withUnsafeMutableBufferPointer { redBuffer in
            green.withUnsafeMutableBufferPointer { greenBuffer in
                blue.withUnsafeMutableBufferPointer { blueBuffer in
                    CGGetDisplayTransferByTable(
                        display,
                        capacity,
                        redBuffer.baseAddress,
                        greenBuffer.baseAddress,
                        blueBuffer.baseAddress,
                        &count
                    )
                }
            }
        }
        guard result == .success, count > 0, count <= capacity else {
            throw ShadeFailure(message: "Cannot read display gamma. Display will stay on.")
        }
        return GammaSnapshot(
            red: Array(red.prefix(Int(count))),
            green: Array(green.prefix(Int(count))),
            blue: Array(blue.prefix(Int(count)))
        )
    }

    static func black(display: CGDirectDisplayID) throws {
        let zero = [CGGammaValue](repeating: 0, count: 2)
        let result = zero.withUnsafeBufferPointer { buffer in
            CGSetDisplayTransferByTable(display, UInt32(buffer.count), buffer.baseAddress, buffer.baseAddress, buffer.baseAddress)
        }
        guard result == .success else {
            throw ShadeFailure(message: "Could not dim a display with gamma control.")
        }
    }

    func restore(display: CGDirectDisplayID) throws {
        guard red.count == green.count, red.count == blue.count, !red.isEmpty else {
            throw ShadeFailure(message: "Saved display gamma is invalid.")
        }
        let result = red.withUnsafeBufferPointer { redBuffer in
            green.withUnsafeBufferPointer { greenBuffer in
                blue.withUnsafeBufferPointer { blueBuffer in
                    CGSetDisplayTransferByTable(
                        display,
                        UInt32(redBuffer.count),
                        redBuffer.baseAddress,
                        greenBuffer.baseAddress,
                        blueBuffer.baseAddress
                    )
                }
            }
        }
        guard result == .success else {
            throw ShadeFailure(message: "Could not restore display gamma.")
        }
    }
}

enum ClamshellState {
    static func decode(_ value: Any?) -> Bool {
        (value as? NSNumber)?.boolValue == true
    }

    static func isClosed() -> Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(rootDomain) }
        guard let value = IORegistryEntryCreateCFProperty(
            rootDomain,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else { return false }
        return decode(value)
    }
}

final class AwakeHold {
    private var process: Process?
    var isRunning: Bool {
        process?.isRunning == true
    }

    func start() throws {
        if process?.isRunning == true {
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // -w binds the assertions to Shade's lifetime, including a crash.
        // -t keeps UserIsActive alive beyond caffeinate's default five seconds.
        // -s also prevents system sleep on AC power while the lid is closed.
        p.arguments = Self.arguments(parentPID: getpid())
        try p.run()
        process = p
    }

    static func arguments(parentPID: Int32) -> [String] {
        ["-d", "-i", "-s", "-u", "-t", "28800", "-w", String(parentPID)]
    }

    func stop() {
        if process?.isRunning == true {
            process?.terminate()
        }; process = nil
    }

    deinit { stop() }
}

/// The child restores brightness when its parent's pipe closes, even on SIGKILL.
final class RestoreGuard {
    private var process: Process?
    var isRunning: Bool {
        process?.isRunning == true
    }

    private var pipe: Pipe?
    func start(snapshots: [DisplaySnapshot]) throws {
        guard !snapshots.isEmpty else { throw ShadeFailure(message: "No displays are available to recover.") }
        guard let executable = Bundle.main.executableURL else { throw ShadeFailure(message: "Could not start display recovery.") }
        let p = Process(), input = Pipe(), ready = Pipe()
        p.executableURL = executable
        p.arguments = ["--restore-guard"] + snapshots.map { $0.method.guardArgument(display: $0.id) }
        p.standardInput = input
        p.standardOutput = ready
        try p.run()
        // Child confirms that it captured every recovery value before we dim.
        var descriptor = pollfd(fd: ready.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 3000) > 0 else {
            try? input.fileHandleForWriting.close()
            if p.isRunning {
                p.terminate()
            }
            throw ShadeFailure(message: "Display recovery setup timed out.")
        }
        let ack = ready.fileHandleForReading.readData(ofLength: 1)
        guard ack == Data([1]) else {
            try? input.fileHandleForWriting.close()
            throw ShadeFailure(message: "Could not prepare display recovery.")
        }
        process = p; pipe = input
    }

    func finish() {
        // The parent already restored brightness. Disarm the child explicitly.
        // Never spin the main run loop waiting for a child: timers can reenter restore().
        let input = pipe
        pipe = nil; process = nil
        if let input {
            try? input.fileHandleForWriting.write(contentsOf: Data([0x43]))
            try? input.fileHandleForWriting.close()
        }
    }

    func handOff() {
        // Closing without the disarm byte tells the child to perform recovery.
        let input = pipe
        pipe = nil; process = nil
        try? input?.fileHandleForWriting.close()
    }

    deinit { handOff() }
}

func runRestoreGuard() -> Never {
    guard CommandLine.arguments.count >= 3,
          let brightness = try? Brightness() else { exit(1) }
    let snapshots: [DisplaySnapshot] = CommandLine.arguments.dropFirst(2).compactMap { argument in
        let parts = argument.split(separator: ":", maxSplits: 2)
        guard parts.count >= 2,
              let display = CGDirectDisplayID(String(parts[0])),
              let method = DisplayMethodKind(rawValue: String(parts[1])) else { return nil }
        switch method {
        case .brightness:
            guard parts.count == 3,
                  let value = Float(parts[2]), value.isFinite, (0 ... 1).contains(value) else { return nil }
            return DisplaySnapshot(id: display, method: .brightness(value))
        case .gamma:
            guard parts.count == 2,
                  let gamma = try? GammaSnapshot.capture(display: display) else { return nil }
            return DisplaySnapshot(id: display, method: .gamma(gamma))
        }
    }
    guard snapshots.count == CommandLine.arguments.count - 2 else { exit(1) }
    FileHandle.standardOutput.write(Data([1]))
    let command = FileHandle.standardInput.readData(ofLength: 1)
    if command == Data([0x43]) {
        exit(0)
    }
    for attempt in 0 ..< 28_800 {
        if (try? brightness.restore(snapshots)) != nil {
            exit(0)
        }
        // Retry quickly for ordinary transient failures. If the parent exited
        // with the lid closed, remain as the recovery owner until it opens.
        if attempt >= 4, !ClamshellState.isClosed() {
            break
        }
        Thread.sleep(forTimeInterval: attempt < 4 ? 0.2 : 1)
    }
    exit(1)
}

/// Checks the actual supply, not whether the battery is currently charging.
enum PowerSupply {
    static func isOnAdapter() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else { return false }
        return source as String == kIOPMACPowerKey
    }
}
