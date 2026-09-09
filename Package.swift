// swift-tools-version: 6.0
import PackageDescription

let package = Package(name: "Shade", platforms: [.macOS(.v14)], products: [.executable(name: "Shade", targets: ["Shade"])], targets: [.target(name: "ShadeCore"), .executableTarget(name: "Shade", dependencies: ["ShadeCore"]), .testTarget(name: "ShadeCoreTests", dependencies: ["ShadeCore"])], swiftLanguageModes: [.v5])
