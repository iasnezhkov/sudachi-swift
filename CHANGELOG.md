# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims
to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **The xcframework now ships dynamic frameworks instead of static archives.**
  Xcode's previews JIT cannot materialise symbols out of static-archive members,
  so in a consuming app every `#Preview` whose object referenced the FFI symbols
  failed to link (`Symbols not found: _uniffi_sudachi_swift_…`). Each slice is
  now a `sudachi_swiftFFI.framework` wrapping the Rust cdylib, which Xcode
  embeds and signs automatically. The Swift API is unchanged; consumers only
  need to update.
- Running the Swift tests under Swift Build needs a symlink bridge: it copies
  the framework beside `Products/Debug/PackageFrameworks` but only rpaths *into*
  that directory, so `scripts/coverage.sh` links the two before testing.
- The wrapper crate no longer builds a `staticlib`; nothing consumed the 31 MB
  archive once the xcframework went dynamic.

### Added
- **Per-slice `.dSYM`s in the xcframework.** The release profile emits
  line-tables-only debug info, `scripts/build-ios.sh` lifts a `.dSYM` with
  `dsymutil` before stripping each framework binary, and `-create-xcframework`
  gets a `-debug-symbols` per slice. Previously there were no symbols to ship at
  all: consuming apps got `Upload Symbols Failed … did not include a dSYM` on
  every TestFlight upload, and Rust frames in crash reports resolved no further
  than the nearest exported `uniffi_*` symbol. The shipped binaries are as
  stripped as before (2.2 MB, 153 exported symbols per slice), and even with the
  `.dSYM`s the release archive drops from 29.5 MB to 10 MB — a linked dylib is a
  fraction of the static archive it replaces.
- `scripts/build-ios.sh` verifies every slice before packaging it: it must be a
  dylib, carry no embedded LLVM bitcode, export every FFI symbol the generated
  header declares, and ship a `.dSYM` whose UUID matches the binary.
- Frameworks carry an `Info.plist` with the deployment targets declared in
  `Package.swift`, and the Rust builds are pinned to those same targets.

## [0.1.1] - 2026-07-27

### Changed
- **sudachi.rs is no longer a git submodule.** SwiftPM initialises submodules
  recursively on every fresh package checkout, so consumers of this package were
  cloning the entire `sudachi.rs` history — hundreds of megabytes of sources
  nothing in the Swift package graph reads — before compiling a single file, and
  on cold CI that could stall a build for tens of minutes. The Swift package is
  unaffected in every other way: same products, same API, same prebuilt
  `.xcframework`. Consumers only need to update to this version.
- Building from source now fetches the pinned upstream sources on demand:
  `third_party/sudachi.rs.pin` holds the commit SHA and
  `scripts/fetch-sudachi-rs.sh` checks it out (shallow) into the gitignored
  `third_party/sudachi.rs/`. `scripts/build-ios.sh` and
  `scripts/fetch-dictionary.sh` call it automatically; `git clone
  --recurse-submodules` is no longer needed.

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

[0.1.1]: https://github.com/iasnezhkov/sudachi-swift/releases/tag/v0.1.1
[0.1.0]: https://github.com/iasnezhkov/sudachi-swift/releases/tag/v0.1.0
