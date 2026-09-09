// swift-tools-version: 6.0
import PackageDescription

let package = Package(name: "Shade", platforms: [.macOS(.v14)], products: [.executable(name: "Shade", targets: ["Shade"])], dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")], targets: [.target(name: "ShadeCore"), .executableTarget(name: "Shade", dependencies: ["ShadeCore", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]), .testTarget(name: "ShadeCoreTests", dependencies: ["ShadeCore", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])])], swiftLanguageModes: [.v5])
