// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PCMode",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PCMode", targets: ["WinApp"])],
    targets: [.executableTarget(name: "WinApp")]
)
