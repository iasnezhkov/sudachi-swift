//! Dictionary-backed integration tests for the Rust FFI wrapper.
//!
//! These exercise the tokenizer hot paths that the pure unit tests in `lib.rs`
//! cannot reach without a dictionary (`run_full`, `run_lite`, and every
//! `tokenize*` method, including their error paths). They are gated on the core
//! dictionary being present at `dictionaries/system_core.dic` — fetch it with
//! `scripts/fetch-dictionary.sh core`, or point `SUDACHI_DICT_DIR` elsewhere.
//! When the dictionary is absent each test is a no-op, mirroring the Swift
//! suite's `.enabled(if:)` skip so the run is honest rather than red.

use std::path::PathBuf;
use std::sync::Arc;

use sudachi_swift::{
    katakana_to_hiragana, SplitMode, SudachiDictionary, SudachiError, SudachiTokenizer,
};

fn resource_dir() -> String {
    if let Ok(dir) = std::env::var("SUDACHI_DICT_DIR") {
        return dir;
    }
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../dictionaries")
        .canonicalize()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|_| "../../dictionaries".to_string())
}

fn dict_available() -> bool {
    PathBuf::from(resource_dir())
        .join("system_core.dic")
        .is_file()
}

fn make_tokenizer(mode: SplitMode) -> SudachiTokenizer {
    let dir = resource_dir();
    let dict = SudachiDictionary::new(format!("{dir}/system_core.dic"), vec![], dir)
        .expect("core dictionary should load");
    SudachiTokenizer::new(Arc::new(dict), mode).expect("tokenizer should build")
}

/// Skip (no-op pass) when the core dictionary is not present.
macro_rules! require_dict {
    () => {
        if !dict_available() {
            eprintln!(
                "skipping: core dictionary not present at {}",
                resource_dir()
            );
            return;
        }
    };
}

#[test]
fn loads_and_tokenizes_full_morphemes() {
    require_dict!();
    let tok = make_tokenizer(SplitMode::C);
    let ms = tok.tokenize("今日は良い天気ですね。".to_string()).unwrap();
    assert!(!ms.is_empty());
    let joined: String = ms.iter().map(|m| m.surface.as_str()).collect();
    assert_eq!(joined, "今日は良い天気ですね。");

    // Touch every full-morpheme field so `run_full`'s mapping is fully exercised.
    let m = &ms[0];
    assert!(m.begin <= m.end);
    let _ = (
        &m.reading_form,
        &m.dictionary_form,
        &m.normalized_form,
        &m.part_of_speech,
        &m.synonym_group_ids,
        m.is_oov,
        m.word_id,
    );
    assert_eq!(katakana_to_hiragana("テンキ".to_string()), "てんき");
}

#[test]
fn tokenize_with_mode_restores_default() {
    require_dict!();
    let tok = make_tokenizer(SplitMode::C);
    let split = tok
        .tokenize_with_mode("国家公務員".to_string(), SplitMode::A)
        .unwrap();
    let whole = tok.tokenize("国家公務員".to_string()).unwrap();
    assert!(split.len() >= whole.len());
    // Default mode (C) must be intact after an explicit-mode call.
    let again = tok.tokenize("国家公務員".to_string()).unwrap();
    assert_eq!(
        again.iter().map(|m| &m.surface).collect::<Vec<_>>(),
        whole.iter().map(|m| &m.surface).collect::<Vec<_>>(),
    );
}

#[test]
fn lite_and_batch_paths() {
    require_dict!();
    let tok = make_tokenizer(SplitMode::C);

    let lite = tok.tokenize_lite("勉強する".to_string()).unwrap();
    assert!(!lite.is_empty());
    let l = &lite[0];
    let _ = (
        &l.dictionary_form,
        &l.reading_form,
        &l.part_of_speech,
        l.pos_id,
    );

    let lite_a = tok
        .tokenize_lite_with_mode("国家公務員".to_string(), SplitMode::A)
        .unwrap();
    let lite_c = tok
        .tokenize_lite_with_mode("国家公務員".to_string(), SplitMode::C)
        .unwrap();
    assert!(lite_a.len() >= lite_c.len());

    let many = tok
        .tokenize_many(vec!["今日は".to_string(), String::new()])
        .unwrap();
    assert_eq!(many.len(), 2);
    assert!(many[1].is_empty()); // empty input -> empty list, not an error

    let many_mode = tok
        .tokenize_many_with_mode(vec!["今日は".to_string(), "勉強".to_string()], SplitMode::A)
        .unwrap();
    assert_eq!(many_mode.len(), 2);
}

#[test]
fn overlong_input_errors_on_every_path() {
    require_dict!();
    let tok = make_tokenizer(SplitMode::C);
    // > MAX_LENGTH (u16::MAX / 4 * 3 = 49_149 bytes) -> InputTooLong, which
    // classifies as SudachiError::Tokenization.
    let huge = "a".repeat(60_000);

    assert!(matches!(
        tok.tokenize(huge.clone()),
        Err(SudachiError::Tokenization { .. })
    ));
    assert!(tok.tokenize_lite(huge.clone()).is_err());
    assert!(tok.tokenize_with_mode(huge.clone(), SplitMode::A).is_err());
    assert!(tok
        .tokenize_lite_with_mode(huge.clone(), SplitMode::A)
        .is_err());
    assert!(tok.tokenize_many(vec![huge.clone()]).is_err());

    // Batch-with-mode must propagate the first item's error (covers the break
    // arm) and still restore the default mode afterwards.
    let batch = tok.tokenize_many_with_mode(vec!["ok".to_string(), huge], SplitMode::A);
    assert!(batch.is_err());
    assert!(tok.tokenize("今日".to_string()).is_ok());
}
