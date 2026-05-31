use std::path::PathBuf;
use std::sync::Arc;

use parking_lot::Mutex;
use thiserror::Error;

use sudachi::analysis::Mode as SudachiMode;
use sudachi::analysis::mlist::MorphemeList;
use sudachi::analysis::stateful_tokenizer::StatefulTokenizer;
use sudachi::config::ConfigBuilder;
use sudachi::dic::dictionary::JapaneseDictionary;

uniffi::include_scaffolding!("suji_sudachi");

/// Default `sudachi.json` baked into the binary. Source:
/// `third_party/sudachi.rs/resources/sudachi.json` (Apache-2.0). Plugin
/// classes here all use bundled implementations — on iOS the DSO fallback
/// is gracefully disabled (`sudachi/src/plugin/loader.rs:70-82`).
const DEFAULT_CONFIG_JSON: &[u8] = include_bytes!("default_config.json");

// ----- Errors -----

#[derive(Debug, Error)]
pub enum SudachiError {
    #[error("Dictionary file not found: {message}")]
    DictionaryNotFound { message: String },
    #[error("Dictionary file invalid: {message}")]
    DictionaryInvalid { message: String },
    #[error("Config invalid: {message}")]
    ConfigInvalid { message: String },
    #[error("Tokenization failed: {message}")]
    Tokenization { message: String },
}

impl From<sudachi::error::SudachiError> for SudachiError {
    fn from(e: sudachi::error::SudachiError) -> Self {
        use sudachi::error::SudachiError as S;
        let msg = format!("{}", e);
        // Heuristic mapping: sudachi uses a thiserror enum but exposes
        // it via a single SudachiError. We classify by surface text so the
        // Swift consumer can show meaningful errors.
        match e {
            S::ConfigError(_) => Self::ConfigInvalid { message: msg },
            _ if msg.contains("No such file") || msg.contains("not found") => {
                Self::DictionaryNotFound { message: msg }
            }
            _ if msg.contains("Invalid") || msg.contains("invalid") => {
                Self::DictionaryInvalid { message: msg }
            }
            _ => Self::Tokenization { message: msg },
        }
    }
}

// ----- Split mode -----

#[derive(Clone, Copy, Debug)]
pub enum SplitMode {
    A,
    B,
    C,
}

impl From<SplitMode> for SudachiMode {
    fn from(m: SplitMode) -> Self {
        match m {
            SplitMode::A => SudachiMode::A,
            SplitMode::B => SudachiMode::B,
            SplitMode::C => SudachiMode::C,
        }
    }
}

// ----- Morpheme (FFI value type) -----

pub struct Morpheme {
    pub surface: String,
    pub reading_form: String,
    pub dictionary_form: String,
    pub normalized_form: String,
    pub part_of_speech: Vec<String>,
    pub synonym_group_ids: Vec<u32>,
    pub is_oov: bool,
    pub word_id: u32,
    pub begin: u32,
    pub end: u32,
}

// ----- Morpheme (compact FFI value type) -----

/// Lean morpheme carrying only the fields the Swift display/merge pipeline
/// consumes, with `part_of_speech` pre-joined into a single comma string
/// and a raw `pos_id` for cheap integer checks. See `tokenize_lite`.
pub struct MorphemeLite {
    pub surface: String,
    pub dictionary_form: String,
    pub reading_form: String,
    pub part_of_speech: String,
    pub pos_id: u16,
}

// ----- Dictionary -----

pub struct SudachiDictionary {
    inner: Arc<JapaneseDictionary>,
}

impl SudachiDictionary {
    pub fn new(
        system_dict_path: String,
        user_dict_paths: Vec<String>,
        resource_dir: String,
    ) -> Result<Self, SudachiError> {
        let mut builder = ConfigBuilder::from_bytes(DEFAULT_CONFIG_JSON)
            .map_err(|e| SudachiError::ConfigInvalid {
                message: format!("{}", e),
            })?
            .system_dict(PathBuf::from(&system_dict_path))
            .resource_path(PathBuf::from(&resource_dir));

        for udp in &user_dict_paths {
            builder = builder.user_dict(PathBuf::from(udp));
        }

        let config = builder.build();
        let dict =
            JapaneseDictionary::from_cfg(&config).map_err(SudachiError::from)?;
        Ok(Self {
            inner: Arc::new(dict),
        })
    }
}

// ----- Tokenizer -----

pub struct SudachiTokenizer {
    dict: Arc<JapaneseDictionary>,
    default_mode: SudachiMode,
    tok: Mutex<StatefulTokenizer<Arc<JapaneseDictionary>>>,
}

impl SudachiTokenizer {
    pub fn new(
        dictionary: Arc<SudachiDictionary>,
        mode: SplitMode,
    ) -> Result<Self, SudachiError> {
        let sudachi_mode: SudachiMode = mode.into();
        let tok = StatefulTokenizer::new(dictionary.inner.clone(), sudachi_mode);
        Ok(Self {
            dict: dictionary.inner.clone(),
            default_mode: sudachi_mode,
            tok: Mutex::new(tok),
        })
    }

    pub fn tokenize(&self, text: String) -> Result<Vec<Morpheme>, SudachiError> {
        self.tokenize_with_mode(text, mode_from(self.default_mode))
    }

    pub fn tokenize_with_mode(
        &self,
        text: String,
        mode: SplitMode,
    ) -> Result<Vec<Morpheme>, SudachiError> {
        let mut tok = self.tok.lock();
        let restore = tok.set_mode(mode.into());

        tok.reset().push_str(&text);
        let tokenize_result = tok.do_tokenize();

        // restore mode whether tokenization succeeded or not so we don't
        // leak state into the next call.
        let _ = tok.set_mode(restore);
        tokenize_result?;

        let mut morphemes = MorphemeList::empty(self.dict.clone());
        morphemes.collect_results(&mut *tok)?;

        let result: Vec<Morpheme> = morphemes
            .iter()
            .map(|m| Morpheme {
                surface: m.surface().to_string(),
                reading_form: m.reading_form().to_string(),
                dictionary_form: m.dictionary_form().to_string(),
                normalized_form: m.normalized_form().to_string(),
                part_of_speech: m.part_of_speech().to_vec(),
                synonym_group_ids: m.synonym_group_ids().to_vec(),
                is_oov: m.is_oov(),
                word_id: m.word_id().as_raw(),
                // Use char offsets (codepoint-indexed), not byte offsets —
                // Swift String indexing is grapheme/scalar based, so byte
                // indices misalign on every kanji.
                begin: m.begin_c() as u32,
                end: m.end_c() as u32,
            })
            .collect();

        Ok(result)
    }

    // ----- Lean / batch API (additive; existing methods unchanged) -----

    /// Lean single-text tokenize. See `MorphemeLite`.
    pub fn tokenize_lite(
        &self,
        text: String,
    ) -> Result<Vec<MorphemeLite>, SudachiError> {
        self.tokenize_lite_with_mode(text, mode_from(self.default_mode))
    }

    /// Lean single-text tokenize with an explicit split mode.
    pub fn tokenize_lite_with_mode(
        &self,
        text: String,
        mode: SplitMode,
    ) -> Result<Vec<MorphemeLite>, SudachiError> {
        let mut tok = self.tok.lock();
        let restore = tok.set_mode(mode.into());
        let result = self.tokenize_lite_locked(&mut tok, &text);
        // restore mode whether tokenization succeeded or not so we don't
        // leak state into the next call.
        let _ = tok.set_mode(restore);
        result
    }

    /// Batch tokenize using the tokenizer's default mode.
    pub fn tokenize_many(
        &self,
        texts: Vec<String>,
    ) -> Result<Vec<Vec<MorphemeLite>>, SudachiError> {
        self.tokenize_many_with_mode(texts, mode_from(self.default_mode))
    }

    /// Batch tokenize with an explicit split mode, holding the lock once for
    /// the whole batch so we pay a single FFI crossing and a single lock.
    pub fn tokenize_many_with_mode(
        &self,
        texts: Vec<String>,
        mode: SplitMode,
    ) -> Result<Vec<Vec<MorphemeLite>>, SudachiError> {
        let mut tok = self.tok.lock();
        let restore = tok.set_mode(mode.into());

        let mut out = Vec::with_capacity(texts.len());
        let mut error = None;
        for text in &texts {
            match self.tokenize_lite_locked(&mut tok, text) {
                Ok(v) => out.push(v),
                Err(e) => {
                    error = Some(e);
                    break;
                }
            }
        }

        let _ = tok.set_mode(restore);
        match error {
            Some(e) => Err(e),
            None => Ok(out),
        }
    }

    /// Shared core for the lean API: tokenize one string into `MorphemeLite`
    /// with the tokenizer already locked and its mode already set. The
    /// caller is responsible for mode restore.
    fn tokenize_lite_locked(
        &self,
        tok: &mut StatefulTokenizer<Arc<JapaneseDictionary>>,
        text: &str,
    ) -> Result<Vec<MorphemeLite>, SudachiError> {
        tok.reset().push_str(text);
        tok.do_tokenize()?;

        let mut morphemes = MorphemeList::empty(self.dict.clone());
        morphemes.collect_results(tok)?;

        let result: Vec<MorphemeLite> = morphemes
            .iter()
            .map(|m| MorphemeLite {
                surface: m.surface().to_string(),
                dictionary_form: m.dictionary_form().to_string(),
                reading_form: m.reading_form().to_string(),
                // Pre-join here so Swift doesn't marshal 6 strings per token
                // just to `.joined(",")` them on the other side.
                part_of_speech: m.part_of_speech().join(","),
                pos_id: m.part_of_speech_id(),
            })
            .collect();

        Ok(result)
    }
}

fn mode_from(m: SudachiMode) -> SplitMode {
    match m {
        SudachiMode::A => SplitMode::A,
        SudachiMode::B => SplitMode::B,
        SudachiMode::C => SplitMode::C,
    }
}

// ----- Free helpers -----

/// Convert Sudachi-style katakana reading to hiragana for furigana display.
/// Only affects the katakana block (U+30A1..U+30F6); other characters pass
/// through unchanged.
pub fn katakana_to_hiragana(s: String) -> String {
    s.chars()
        .map(|c| {
            let cp = c as u32;
            if (0x30A1..=0x30F6).contains(&cp) {
                char::from_u32(cp - 0x60).unwrap_or(c)
            } else {
                c
            }
        })
        .collect()
}
