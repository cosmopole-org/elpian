// swift-tools-version:5.9
import PackageDescription

/// The Elpian iOS engine. `ElpianCore` is the pure-Swift port of the
/// TypeScript core (native/core/src): Swift + Foundation only, so it builds
/// and tests on Linux as well as on Apple platforms.
let package = Package(
    name: "Elpian",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ElpianCore", targets: ["ElpianCore"]),
    ],
    targets: [
        .target(name: "ElpianCore", path: "Sources/ElpianCore"),
        .testTarget(name: "ElpianCoreTests", dependencies: ["ElpianCore"], path: "Tests/ElpianCoreTests"),
    ],
    swiftLanguageVersions: [.v5]
)
