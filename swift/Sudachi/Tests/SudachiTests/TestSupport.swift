import Foundation
import Sudachi

/// Shared dictionary fixture for the test suites. Dictionary-dependent tests
/// are gated on `isAvailable` via `@Test(.enabled(if:))`, so they are reported
/// as *skipped* (not failed, not fake-passing) when the dictionary has not been
/// downloaded. Fetch it with `scripts/fetch-dictionary.sh core`, or point at a
/// custom location with the `SUDACHI_DICT_DIR` environment variable.
enum DictFixture {
    static let resourceDir: String = {
        if let env = ProcessInfo.processInfo.environment["SUDACHI_DICT_DIR"] {
            return env
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SudachiTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // Sudachi/
            .deletingLastPathComponent()  // swift/
            .deletingLastPathComponent()  // <repo root>
            .appendingPathComponent("dictionaries")
            .path
    }()

    static let systemDictPath = "\(resourceDir)/system_core.dic"

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: systemDictPath)
    }

    static func makeDictionary() throws -> SudachiDictionary {
        try SudachiDictionary(
            systemDictPath: systemDictPath,
            userDictPaths: [],
            resourceDir: resourceDir
        )
    }
}
