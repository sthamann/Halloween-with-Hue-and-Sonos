// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "HalloweenSonos",
    defaultLocalization: "de", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "HalloweenCore", type: .static, targets: ["HalloweenCore"]), .executable(name: "HalloweenSonos", targets: ["HalloweenApp"])], targets: [.target(name: "HalloweenCore"), .executableTarget(name: "HalloweenApp", dependencies: ["HalloweenCore"], resources: [.process("Resources")]), .testTarget(name: "HalloweenCoreTests", dependencies: ["HalloweenCore"])])
