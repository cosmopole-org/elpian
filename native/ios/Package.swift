// swift-tools-version:5.9
import Foundation
import PackageDescription

/// The Elpian iOS engine.
///
///  - `ElpianCore` is the pure-Swift port of the TypeScript engine (native/web)
///    (native/web/src): Swift + Foundation only, so it builds and tests on
///    Linux as well as on Apple platforms.
///  - `CElpianVM` is the C module for the Rust runtime's ABI
///    (rust/crates/elpian-ffi/include/elpian_vm.h, copied by
///    scripts/sync-assets.sh; a test keeps the copy equal to the source).
///  - `Elpian` is the UIKit host (the counterpart of native/android/elpian):
///    every file is wrapped in `#if canImport(UIKit)`, so on Linux it compiles
///    to an empty module.
///
/// The Rust library itself is optional at build time:
///
///  - when `Frameworks/ElpianVM.xcframework` exists (built by
///    `scripts/build-rust.sh`), it is added as a binary target, linked into
///    `Elpian`, and `ELPIAN_VM_LINKED` is defined so `IOSElpianVm` calls the
///    C ABI directly;
///  - with `ELPIAN_VM_LINK=1` in the environment, `Elpian` links
///    `libelpian_vm` by name instead (the host app supplies the search path)
///    and `ELPIAN_VM_LINKED` is defined too;
///  - otherwise nothing is linked and `IOSElpianVm` resolves the exports at
///    run time with `dlsym` (e.g. a library the host app links or embeds
///    itself); with none present it reports the runtime unavailable.
///
/// `ELPIAN_VM_XCFRAMEWORK=0` ignores an existing xcframework.
let environment = ProcessInfo.processInfo.environment
let xcframeworkPath = "Frameworks/ElpianVM.xcframework"
let hasXCFramework = environment["ELPIAN_VM_XCFRAMEWORK"] != "0"
    && FileManager.default.fileExists(atPath: Context.packageDirectory + "/" + xcframeworkPath)
let linkByName = environment["ELPIAN_VM_LINK"] == "1"

var elpianDependencies: [Target.Dependency] = [
    "ElpianCore",
    "CElpianVM",
    // WasmKit backs the WASM runtime on Apple platforms only, so a Linux
    // `swift build` of the core never compiles it.
    .product(name: "WasmKit", package: "WasmKit", condition: .when(platforms: [.iOS, .macOS])),
]
var elpianSwiftSettings: [SwiftSetting] = []
var elpianLinkerSettings: [LinkerSetting] = []
var extraTargets: [Target] = []

if hasXCFramework {
    extraTargets.append(.binaryTarget(name: "ElpianVM", path: xcframeworkPath))
    elpianDependencies.append(.target(name: "ElpianVM", condition: .when(platforms: [.iOS])))
    elpianSwiftSettings.append(.define("ELPIAN_VM_LINKED", .when(platforms: [.iOS])))
} else if linkByName {
    elpianLinkerSettings.append(.linkedLibrary("elpian_vm", .when(platforms: [.iOS, .macOS])))
    elpianSwiftSettings.append(.define("ELPIAN_VM_LINKED", .when(platforms: [.iOS, .macOS])))
}

let package = Package(
    name: "Elpian",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ElpianCore", targets: ["ElpianCore"]),
        .library(name: "Elpian", targets: ["Elpian"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftwasm/WasmKit", .upToNextMinor(from: "0.2.0")),
    ],
    targets: [
        .target(name: "ElpianCore", path: "Sources/ElpianCore"),
        .target(name: "CElpianVM", path: "Sources/CElpianVM"),
        .target(
            name: "Elpian",
            dependencies: elpianDependencies,
            path: "Sources/Elpian",
            resources: [.copy("Resources/Fonts")],
            swiftSettings: elpianSwiftSettings,
            linkerSettings: elpianLinkerSettings
        ),
        .testTarget(name: "ElpianCoreTests", dependencies: ["ElpianCore"], path: "Tests/ElpianCoreTests"),
    ] + extraTargets,
    swiftLanguageVersions: [.v5]
)
