import AppKit
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
    func internalDisplay() throws -> CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success,
              let id = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 })
        else {
            throw ShadeFailure(message: "No built-in display found.")
        }
        return id
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
        p.arguments = ["-d", "-i", "-u", "-t", "28800", "-w", String(getpid())]
        try p.run()
        process = p
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
    func start(display: UInt32, brightness: Float) throws {
        guard let executable = Bundle.main.executableURL else { throw ShadeFailure(message: "Could not start display recovery.") }
        let p = Process(), input = Pipe(), ready = Pipe()
        p.executableURL = executable
        p.arguments = ["--restore-guard", String(display), String(brightness)]
        p.standardInput = input
        p.standardOutput = ready
        try p.run()
        // Child confirms that it has loaded the brightness API before we dim.
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

    deinit { finish() }
}

func runRestoreGuard() -> Never {
    guard CommandLine.arguments.count == 4,
          let display = UInt32(CommandLine.arguments[2]),
          let original = Float(CommandLine.arguments[3]), original.isFinite, (0 ... 1).contains(original),
          let brightness = try? Brightness() else { exit(1) }
    FileHandle.standardOutput.write(Data([1]))
    let command = FileHandle.standardInput.readData(ofLength: 1)
    if command == Data([0x43]) {
        exit(0)
    }
    for _ in 0 ..< 5 {
        if (try? brightness.set(display, original)) != nil {
            exit(0)
        }
        Thread.sleep(forTimeInterval: 0.2)
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
