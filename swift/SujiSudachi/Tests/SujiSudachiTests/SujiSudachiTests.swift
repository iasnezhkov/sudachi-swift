import Testing
import Foundation
@testable import SujiSudachi

@Suite("SujiSudachi end-to-end")
struct SujiSudachiTests {

    /// Walks up from this source file to the repo root, then to the
    /// `dictionaries/` directory the `fetch-dictionary.sh` script populates.
    /// Override with `SUDACHI_DICT_DIR` env var if your layout differs.
    private static let resourceDir: String = {
        if let env = ProcessInfo.processInfo.environment["SUDACHI_DICT_DIR"] {
            return env
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SujiSudachiTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // SujiSudachi/
            .deletingLastPathComponent() // swift/
            .deletingLastPathComponent() // <repo root>
            .appendingPathComponent("dictionaries")
            .path
    }()

    private static let systemDictPath = "\(resourceDir)/system_core.dic"

    private static var dictionaryAvailable: Bool {
        FileManager.default.fileExists(atPath: systemDictPath)
    }

    @Test
    func dictionaryLoads() throws {
        guard Self.dictionaryAvailable else {
            Issue.record("Dictionary not downloaded — run scripts/fetch-dictionary.sh")
            return
        }
        _ = try SudachiDictionary(systemDictPath: Self.systemDictPath, userDictPaths: [], resourceDir: Self.resourceDir)
    }

    @Test
    func tokenizesBaselineSentence() throws {
        guard Self.dictionaryAvailable else {
            Issue.record("Dictionary not downloaded — run scripts/fetch-dictionary.sh")
            return
        }
        let dict = try SudachiDictionary(systemDictPath: Self.systemDictPath, userDictPaths: [], resourceDir: Self.resourceDir)
        let tok = try SudachiTokenizer(dictionary: dict, mode: .c)
        let morphemes = try tok.tokenize(text: "今日は良い天気ですね。")

        #expect(!morphemes.isEmpty)
        let surfaces = morphemes.map { $0.surface }.joined()
        #expect(surfaces == "今日は良い天気ですね。")
    }

    @Test
    func multiGranularityCompound() throws {
        guard Self.dictionaryAvailable else {
            Issue.record("Dictionary not downloaded — run scripts/fetch-dictionary.sh")
            return
        }
        // Sudachi's headline: 国家公務員 ('national civil servant').
        // C keeps it whole, B splits 国家+公務員, A splits 国家+公務+員.
        let dict = try SudachiDictionary(systemDictPath: Self.systemDictPath, userDictPaths: [], resourceDir: Self.resourceDir)

        let tokC = try SudachiTokenizer(dictionary: dict, mode: .c)
        let surfacesC = try tokC.tokenize(text: "国家公務員").map { $0.surface }
        #expect(surfacesC == ["国家公務員"])

        let tokA = try SudachiTokenizer(dictionary: dict, mode: .a)
        let surfacesA = try tokA.tokenize(text: "国家公務員").map { $0.surface }
        #expect(surfacesA.count >= 2)
    }
}
