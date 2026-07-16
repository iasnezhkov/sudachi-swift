# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims
to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-16

First public release.

### Added
- Swift bindings to [sudachi.rs](https://github.com/WorksApplications/sudachi.rs)
  (pinned to v0.6.11) via UniFFI: `SudachiDictionary`, `SudachiTokenizer`,
  `Morpheme`, `SplitMode` (A/B/C), and a `SudachiError` taxonomy conforming to
  `LocalizedError`.
- `tokenize` / `tokenizeWithMode` — full-fidelity tokenization, including
  re-tokenizing a substring at a different granularity.
- Lean API: `MorphemeLite` (compact morpheme with `partOfSpeech` pre-joined and
  an integer `posId`) via `tokenizeLite` / `tokenizeLiteWithMode` — roughly half
  the FFI marshalling of the full path.
- Batch API: `tokenizeMany` / `tokenizeManyWithMode` — many strings in a single
  FFI crossing under one lock, for document/catalog-scale workloads.
- Codepoint-based morpheme offsets (`begin`/`end`) safe for Swift `String`
  indexing, plus the `Morpheme.range(in:)` convenience.
- `SudachiDictionary(systemDictionary:userDictionaries:)` — URL-based
  convenience initializer matching the `fetch-dictionary.sh` directory layout.
- `katakanaToHiragana` helper for furigana display.
- Distribution: SPM package with a prebuilt binary `.xcframework`
  (arm64 iOS device / simulator / macOS); iOS 17+, macOS 14+.
- Tooling: build, dictionary-fetch, lint, and coverage scripts; CI with
  rustfmt + clippy + swift-format and 100% line-coverage gates on the
  hand-written layers; manual release workflow that rewrites the binary
  target URL/checksum atomically with the tag.

[0.1.0]: https://github.com/iasnezhkov/sudachi-swift/releases/tag/v0.1.0
