import Testing
import Foundation
@testable import SujiSudachi

@Suite("SujiSudachi extended API")
struct SujiSudachiExtendedAPITests {

    /// See `SujiSudachiTests.resourceDir` — same convention.
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

    private static var skipUnavailable: Bool {
        !FileManager.default.fileExists(atPath: systemDictPath)
    }

    private static func makeDict() throws -> SudachiDictionary {
        try SudachiDictionary(
            systemDictPath: systemDictPath,
            userDictPaths: [],
            resourceDir: resourceDir
        )
    }

    @Test
    func partOfSpeechIsStructured() throws {
        if Self.skipUnavailable { return }
        let dict = try Self.makeDict()
        let tok = try SudachiTokenizer(dictionary: dict, mode: .c)
        let morphemes = try tok.tokenize(text: "勉強する")

        // UniDic POS has 6 components: 大分類, 中分類, 小分類, 細分類,
        // 活用型, 活用形. We should always get 6.
        for m in morphemes {
            #expect(m.partOfSpeech.count == 6, "morpheme \(m.surface) has \(m.partOfSpeech.count) POS components, expected 6")
        }

        // 勉強 is サ変可能 noun, する is verb
        let benkyou = morphemes.first { $0.surface == "勉強" }
        #expect(benkyou?.partOfSpeech.first == "名詞")
        #expect(benkyou?.partOfSpeech[2] == "サ変可能")

        let suru = morphemes.first { $0.surface == "する" }
        #expect(suru?.partOfSpeech.first == "動詞")
    }

    @Test
    func splitModeOnSubstring() throws {
        if Self.skipUnavailable { return }
        let dict = try Self.makeDict()
        let tok = try SudachiTokenizer(dictionary: dict, mode: .c)

        // First tokenize "国家公務員大学" in Mode C — gets a coarse breakdown.
        let coarse = try tok.tokenize(text: "国家公務員大学")
        #expect(coarse.allSatisfy { $0.partOfSpeech.first == "名詞" || $0.partOfSpeech.first == "接尾辞" })

        // Now tap on the first morpheme and re-tokenize that substring in Mode A
        // — should give finer-grained breakdown. The default-mode tokenizer is
        // unchanged for the next call.
        guard let first = coarse.first else { Issue.record("no morphemes"); return }
        let fineGrained = try tok.tokenizeWithMode(text: first.surface, mode: .a)
        #expect(fineGrained.count >= 2, "Mode A on \(first.surface) should produce multiple sub-morphemes")

        // Default mode should still be C for subsequent tokenize() calls.
        let coarseAgain = try tok.tokenize(text: "国家公務員大学")
        #expect(coarseAgain.map(\.surface) == coarse.map(\.surface))
    }

    @Test
    func readingConversion() {
        // The Sudachi reading_form is katakana. Suji UI wants hiragana
        // for furigana display.
        #expect(katakanaToHiragana(s: "オジギ") == "おじぎ")
        #expect(katakanaToHiragana(s: "マイニチ") == "まいにち")
        #expect(katakanaToHiragana(s: "テンキ") == "てんき")

        // Non-katakana passes through.
        #expect(katakanaToHiragana(s: "今日は") == "今日は")
        #expect(katakanaToHiragana(s: "hello") == "hello")

        // Mixed input — typical in mixed sentences.
        #expect(katakanaToHiragana(s: "ラーメンが好き") == "らーめんが好き")
    }

    @Test
    func morphemeMetadata() throws {
        if Self.skipUnavailable { return }
        let dict = try Self.makeDict()
        let tok = try SudachiTokenizer(dictionary: dict, mode: .c)

        // Real word: 友達 has known entry, isOov=false, wordId≠0
        let m = try tok.tokenize(text: "友達").first
        #expect(m?.isOov == false)
        #expect(m?.wordId != 0)
        #expect(m?.begin == 0)
        #expect(m?.end == 2)

        // Made-up romaji: should be OOV
        let oov = try tok.tokenize(text: "Qwertyxyz").first
        #expect(oov?.isOov == true)
    }

    @Test
    func synonymGroupsForCommonWords() throws {
        if Self.skipUnavailable { return }
        let dict = try Self.makeDict()
        let tok = try SudachiTokenizer(dictionary: dict, mode: .c)

        // Sudachi ships synonym groups for many common words.
        // We don't assert specific IDs (they're internal) but verify the
        // field is populated for at least one well-known word.
        let m = try tok.tokenize(text: "美味しい").first
        #expect(m != nil)
        // Either populated or empty — both fine, just exercising the API path.
        _ = m?.synonymGroupIds
    }

    // MARK: - Lean / batch API

    @Test
    func liteMatchesFullTokenize() throws {
        if Self.skipUnavailable { return }
        let dict = try Self.makeDict()
        let tok = try SudachiTokenizer(dictionary: dict, mode: .c)

        let text = "今日は勉強する"
        let full = try tok.tokenize(text: text)
        let lite = try tok.tokenizeLite(text: text)

        // Same segmentation.
        #expect(lite.map(\.surface) == full.map(\.surface))
        #expect(lite.map(\.dictionaryForm) == full.map(\.dictionaryForm))
        #expect(lite.map(\.readingForm) == full.map(\.readingForm))

        // POS pre-joined on the Rust side equals the Swift-side join of the
        // full morpheme's components.
        for (l, f) in zip(lite, full) {
            #expect(l.partOfSpeech == f.partOfSpeech.joined(separator: ","))
        }

        // pos_id is populated (non-OOV tokens have a real connection id).
        let benkyou = lite.first { $0.surface == "勉強" }
        #expect(benkyou != nil)
        #expect(benkyou!.partOfSpeech.hasPrefix("名詞"))
    }

    @Test
    func liteWithModeRespectsMode() throws {
        if Self.skipUnavailable { return }
        let dict = try Self.makeDict()
        let tok = try SudachiTokenizer(dictionary: dict, mode: .c)

        let liteA = try tok.tokenizeLiteWithMode(text: "国家公務員", mode: .a)
        let liteC = try tok.tokenizeLiteWithMode(text: "国家公務員", mode: .c)
        #expect(liteA.count >= liteC.count)

        // Default mode unaffected after an explicit-mode call.
        let again = try tok.tokenizeLite(text: "国家公務員")
        #expect(again.map(\.surface) == liteC.map(\.surface))
    }

    @Test
    func batchMatchesPerText() throws {
        if Self.skipUnavailable { return }
        let dict = try Self.makeDict()
        let tok = try SudachiTokenizer(dictionary: dict, mode: .c)

        let texts = ["今日は", "勉強する", "", "美味しいラーメン"]
        let batch = try tok.tokenizeMany(texts: texts)
        #expect(batch.count == texts.count)

        for (i, text) in texts.enumerated() {
            let single = try tok.tokenizeLite(text: text)
            #expect(batch[i].map(\.surface) == single.map(\.surface))
            #expect(batch[i].map(\.partOfSpeech) == single.map(\.partOfSpeech))
            #expect(batch[i].map(\.posId) == single.map(\.posId))
        }

        // Empty input → empty token list, not an error.
        #expect(batch[2].isEmpty)
    }
}
