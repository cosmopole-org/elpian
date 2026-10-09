import Foundation
import XCTest

/**
 * The Swift package bundles copies of files that live elsewhere in the repo
 * (scripts/sync-assets.sh): the C ABI header of libelpian_vm and the Material
 * Icons font. A copy that drifts from its source fails here — re-run the script.
 */
final class BundledCopiesTests: XCTestCase {
    /** native/ios (this file is native/ios/Tests/ElpianCoreTests/…). */
    private let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func assertSame(_ copy: String, _ source: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let copyURL = packageDir.appendingPathComponent(copy)
        let sourceURL = packageDir.appendingPathComponent(source).standardizedFileURL
        let a = try Data(contentsOf: copyURL)
        let b = try Data(contentsOf: sourceURL)
        XCTAssertEqual(a, b, "\(copy) differs from \(sourceURL.path); run native/ios/scripts/sync-assets.sh", file: file, line: line)
    }

    func testElpianVmHeaderMatchesTheCrate() throws {
        try assertSame("Sources/CElpianVM/include/elpian_vm.h", "../../rust/crates/elpian-ffi/include/elpian_vm.h")
    }

    func testMaterialIconsFontMatchesTheSharedAsset() throws {
        try assertSame("Sources/Elpian/Resources/Fonts/MaterialIcons-Regular.ttf", "../assets/fonts/MaterialIcons-Regular.ttf")
        try assertSame("Sources/Elpian/Resources/Fonts/MaterialIcons-LICENSE.txt", "../assets/fonts/MaterialIcons-LICENSE.txt")
    }
}
