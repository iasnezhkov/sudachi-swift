## What & why

<!-- What does this change and, more importantly, why? -->

## Checklist

- [ ] If the FFI surface changed: updated both `lib.rs` and `sudachi_swift.udl`,
      then ran `scripts/build-ios.sh` and committed the regenerated
      `Sudachi.swift`.
- [ ] Added/updated tests (Rust: `crates/sudachi-swift-uniffi/tests/`,
      Swift: `swift/Sudachi/Tests/`).
- [ ] `cargo fmt --all --check` and
      `cargo clippy -p sudachi-swift-uniffi --all-targets -- -D warnings` pass.
- [ ] `cargo test -p sudachi-swift-uniffi` and
      `cd swift/Sudachi && swift test` pass locally (core dictionary present).
- [ ] `scripts/lint-swift.sh` passes.
- [ ] Updated `README.md` / `CHANGELOG.md` / `docs/ARCHITECTURE.md` if relevant.
- [ ] No build artifacts, dictionaries, or scratch files committed.
