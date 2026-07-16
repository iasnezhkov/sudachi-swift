import Foundation

// Hand-written ergonomic helpers layered on top of the UniFFI-generated API in
// Sudachi.swift. Keep additive, Swift-only conveniences here — never edit the
// generated file.

extension SudachiDictionary {
    /// Opens a dictionary directory laid out like the output of
    /// `scripts/fetch-dictionary.sh` — the system dictionary plus `char.def` /
    /// `unk.def` sitting next to it:
    ///
    /// ```
    /// dictionaries/
    /// ├── system_core.dic
    /// ├── char.def
    /// └── unk.def
    /// ```
    ///
    /// The directory containing `systemDictionary` is used as the resource
    /// directory. Typical app usage, with the dictionary shipped in the bundle:
    ///
    /// ```swift
    /// let url = Bundle.main.url(forResource: "system_core", withExtension: "dic",
    ///                           subdirectory: "SudachiDict")!
    /// let dict = try SudachiDictionary(systemDictionary: url)
    /// ```
    ///
    /// - Parameters:
    ///   - systemDictionary: File URL of the `system_*.dic` to load.
    ///   - userDictionaries: Optional user dictionaries applied on top.
    /// - Throws: `SudachiError.DictionaryNotFound` / `.ConfigInvalid` naming
    ///   the offending path if anything is missing.
    public convenience init(
        systemDictionary: URL,
        userDictionaries: [URL] = []
    ) throws {
        try self.init(
            systemDictPath: systemDictionary.path,
            userDictPaths: userDictionaries.map(\.path),
            resourceDir: systemDictionary.deletingLastPathComponent().path
        )
    }
}

extension Morpheme {
    /// This morpheme's span within `text`, as a `Range<String.Index>`.
    ///
    /// `begin`/`end` are **codepoint** (Unicode scalar) offsets, so they must be
    /// resolved against `text.unicodeScalars` — not treated as UTF-8/UTF-16 or
    /// `Character` offsets. Use this instead of hand-rolling index math:
    ///
    /// ```swift
    /// for m in try tokenizer.tokenize(text: text) {
    ///     if let r = m.range(in: text) { highlight(text[r]) }
    /// }
    /// ```
    ///
    /// Returns `nil` if the offsets fall outside `text` (e.g. the morpheme came
    /// from a different string).
    public func range(in text: String) -> Range<String.Index>? {
        let scalars = text.unicodeScalars
        guard
            let lower = scalars.index(
                scalars.startIndex, offsetBy: Int(begin), limitedBy: scalars.endIndex),
            let upper = scalars.index(
                scalars.startIndex, offsetBy: Int(end), limitedBy: scalars.endIndex),
            lower <= upper
        else { return nil }
        return lower..<upper
    }
}
