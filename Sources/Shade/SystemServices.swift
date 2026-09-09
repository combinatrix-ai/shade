import AppKit
import IOKit.pwr_mgt

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
            throw ShadeFailure(message: "このMacでは輝度の制御を利用できません。")
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
            throw ShadeFailure(message: "内蔵ディスプレイが見つかりません。")
        }
        return id
    }

    func get(_ id: CGDirectDisplayID) throws -> Float {
        var value: Float = 0
        guard getValue(id, &value) == 0, value.isFinite, (0 ... 1).contains(value) else {
            throw ShadeFailure(message: "元の明るさを読み取れませんでした。画面は暗くしません。")
        }
        return value
    }

    func set(_ id: CGDirectDisplayID, _ value: Float) throws {
        guard setValue(id, value) == 0 else { throw ShadeFailure(message: "画面の明るさを変更できませんでした。") }
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
        guard let executable = Bundle.main.executableURL else { throw ShadeFailure(message: "復帰用プロセスを起動できません。") }
        let p = Process(), input = Pipe(), ready = Pipe()
        p.executableURL = executable
        p.arguments = ["--restore-guard", String(display), String(brightness)]
        p.standardInput = input
        p.standardOutput = ready
        try p.run()
        // Child confirms that it has loaded the brightness API before we dim.
        let ack = ready.fileHandleForReading.readData(ofLength: 1)
        guard ack == Data([1]) else {
            try? input.fileHandleForWriting.close()
            throw ShadeFailure(message: "画面の復帰準備に失敗しました。")
        }
        process = p; pipe = input
    }

    func finish() {
        try? pipe?.fileHandleForWriting.close()
        process?.waitUntilExit()
        pipe = nil; process = nil
    }

    deinit { finish() }
}

func runRestoreGuard() -> Never {
    guard CommandLine.arguments.count == 4,
          let display = UInt32(CommandLine.arguments[2]),
          let original = Float(CommandLine.arguments[3]), original.isFinite, (0 ... 1).contains(original),
          let brightness = try? Brightness() else { exit(1) }
    FileHandle.standardOutput.write(Data([1]))
    _ = FileHandle.standardInput.readDataToEndOfFile()
    for _ in 0 ..< 5 {
        if (try? brightness.set(display, original)) != nil {
            exit(0)
        }
        Thread.sleep(forTimeInterval: 0.2)
    }
    exit(1)
}
