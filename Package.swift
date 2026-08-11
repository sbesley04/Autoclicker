// swift-tools-version: 6.0
// Convenience manifest so `swift build` / `swift test` work from a normal
// Xcode toolchain. The canonical way to build the app is Autoclicker.xcodeproj.
import PackageDescription

let package = Package(
    name: "Autoclicker",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Autoclicker",
            path: "Autoclicker",
            exclude: ["Assets.xcassets"]
        ),
        .testTarget(
            name: "AutoclickerTests",
            dependencies: ["Autoclicker"],
            path: "AutoclickerTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
