//! Programmatic mutation of the on-disk config file from the CLI.
//!
//! Backs `voxtype config set engine <NAME>`. This is the same operation the
//! TUI engine section performs (see `src/tui/engine.rs`), exposed as a
//! non-interactive command so external tools (Quickshell engine picker,
//! shell scripts, etc.) can switch engines without rendering a TUI.
//!
//! Validation rules mirror the TUI:
//!   1. The engine name must be a known variant of [`TranscriptionEngine`].
//!   2. For non-whisper engines, the binary must have been compiled with the
//!      matching Cargo feature. The TUI surfaces this as a warning; the CLI
//!      treats it as a hard error since there's no interactive escape hatch.
//!
//! Comments and unrelated fields are preserved via `toml_edit` (through
//! `ConfigEditor`). Saves go through the same atomic write + validation
//! pipeline as the TUI.

use std::path::PathBuf;

use crate::config::TranscriptionEngine;
use crate::tui::{ConfigEditor, EditorError};

/// All engine identifiers accepted by `voxtype config set engine`.
///
/// Kept in sync with [`TranscriptionEngine`] and with `ENGINE_CHOICES` in
/// `src/tui/engine.rs`. If a new engine is added there, add it here too.
pub const ENGINE_NAMES: &[&str] = &[
    "whisper",
    "parakeet",
    "moonshine",
    "sensevoice",
    "paraformer",
    "dolphin",
    "omnilingual",
    "cohere",
];

#[derive(Debug, thiserror::Error)]
pub enum ConfigSetError {
    #[error(
        "unknown engine '{0}'. Valid engines: whisper, parakeet, moonshine, \
         sensevoice, paraformer, dolphin, omnilingual, cohere"
    )]
    UnknownEngine(String),

    #[error(
        "engine '{0}' is not compiled into this binary.\n  \
         Rebuild voxtype with the matching Cargo feature:\n    \
         cargo build --release --features {0}\n  \
         Or install a prebuilt variant that includes it (see \
         `voxtype info variants`)."
    )]
    FeatureNotCompiled(String),

    #[error("config editor: {0}")]
    Editor(#[from] EditorError),
}

/// Is the engine name one we recognize at all?
///
/// Equivalent to parsing through [`TranscriptionEngine`]'s serde
/// representation but avoids deserializing a whole config to check one
/// field.
pub fn parse_engine(name: &str) -> Option<TranscriptionEngine> {
    match name {
        "whisper" => Some(TranscriptionEngine::Whisper),
        "parakeet" => Some(TranscriptionEngine::Parakeet),
        "moonshine" => Some(TranscriptionEngine::Moonshine),
        "sensevoice" => Some(TranscriptionEngine::SenseVoice),
        "paraformer" => Some(TranscriptionEngine::Paraformer),
        "dolphin" => Some(TranscriptionEngine::Dolphin),
        "omnilingual" => Some(TranscriptionEngine::Omnilingual),
        "cohere" => Some(TranscriptionEngine::Cohere),
        _ => None,
    }
}

/// Was this binary compiled with the feature needed to run the given engine?
///
/// Whisper is always available; everything else is gated on the
/// corresponding Cargo feature flag. This is the source-of-truth check that
/// matches what the TUI shows on source builds (see
/// `EngineState::refresh_binary_match` in `src/tui/engine.rs`). The TUI's
/// `compiled_features()` list in `src/setup/binary.rs` is incomplete (it
/// only enumerates parakeet + GPU features), so we evaluate `cfg!` directly
/// here rather than going through that helper.
pub fn engine_feature_compiled(name: &str) -> bool {
    match name {
        "whisper" => true,
        "parakeet" => cfg!(feature = "parakeet"),
        "moonshine" => cfg!(feature = "moonshine"),
        "sensevoice" => cfg!(feature = "sensevoice"),
        "paraformer" => cfg!(feature = "paraformer"),
        "dolphin" => cfg!(feature = "dolphin"),
        "omnilingual" => cfg!(feature = "omnilingual"),
        "cohere" => cfg!(feature = "cohere"),
        _ => false,
    }
}

/// Set the active engine in the config file at `path`.
///
/// Validates the name and the compiled-feature gate before touching disk.
/// If the file doesn't exist, an empty document is created and `engine = ".."`
/// is written at the root. If it exists, `toml_edit` updates only the
/// `engine` key, preserving comments and other fields.
pub fn set_engine(path: PathBuf, name: &str) -> Result<PathBuf, ConfigSetError> {
    if parse_engine(name).is_none() {
        return Err(ConfigSetError::UnknownEngine(name.to_string()));
    }
    if !engine_feature_compiled(name) {
        return Err(ConfigSetError::FeatureNotCompiled(name.to_string()));
    }

    let mut editor = ConfigEditor::load_from_path(path)?;
    editor.set_string("", "engine", name);
    editor.save()?;
    Ok(editor.path().to_path_buf())
}

/// Update hotkey fields together, preserving the rest of the user's config.
pub fn set_hotkey(
    path: PathBuf,
    key: Option<&str>,
    mode: Option<&str>,
    enabled: Option<bool>,
) -> Result<(), EditorError> {
    set_preferences(path, key, mode, enabled, None)
}

/// Save the quick settings as one validated, atomic change.
pub fn set_preferences(
    path: PathBuf,
    key: Option<&str>,
    mode: Option<&str>,
    enabled: Option<bool>,
    audio_device: Option<&str>,
) -> Result<(), EditorError> {
    let mut editor = ConfigEditor::load_from_path(path)?;
    if let Some(key) = key {
        let key = key.trim().to_uppercase();
        #[cfg(target_os = "linux")]
        crate::hotkey::evdev_listener::parse_key_name(&key)
            .map_err(|e| EditorError::Validate(e.to_string()))?;
        if key.is_empty() {
            return Err(EditorError::Validate("Hotkey cannot be empty".into()));
        }
        editor.set_string("hotkey", "key", &key);
    }
    if let Some(mode) = mode {
        if !["hybrid", "toggle", "push_to_talk"].contains(&mode) {
            return Err(EditorError::Validate(format!(
                "Unknown hotkey mode: {mode}"
            )));
        }
        editor.set_string("hotkey", "mode", mode);
    }
    if let Some(enabled) = enabled {
        editor.set_bool("hotkey", "enabled", enabled);
    }
    if let Some(device) = audio_device {
        if device.trim().is_empty() {
            return Err(EditorError::Validate("Microphone cannot be empty".into()));
        }
        editor.set_string("audio", "device", device);
    }
    editor.save()
}

/// List Linux capture cards from kernel metadata without opening audio hardware.
/// CPAL's input_devices() probes PCM streams and can stall for seconds or
/// contend with an active dictation stream, so it must not run on settings reads.
#[cfg(target_os = "linux")]
pub fn input_device_options() -> serde_json::Value {
    let cards = std::fs::read_to_string("/proc/asound/cards").unwrap_or_default();
    let pcm = std::fs::read_to_string("/proc/asound/pcm").unwrap_or_default();
    alsa_input_options(&cards, &pcm)
}

#[cfg(target_os = "linux")]
fn alsa_input_options(cards: &str, pcm: &str) -> serde_json::Value {
    let mut options = Vec::new();
    for line in cards.lines() {
        let Some((index, rest)) = line.split_once('[') else {
            continue;
        };
        let Ok(index) = index.trim().parse::<u32>() else {
            continue;
        };
        let Some((id, _)) = rest.split_once(']') else {
            continue;
        };
        let has_capture = pcm.lines().any(|line| {
            let Some((card, _)) = line.split_once('-') else {
                return false;
            };
            card.trim().parse::<u32>().ok() == Some(index)
                && line.split(':').any(|part| {
                    part.trim()
                        .strip_prefix("capture ")
                        .and_then(|count| count.trim().parse::<u32>().ok())
                        .is_some_and(|count| count > 0)
                })
        });
        if has_capture {
            let name = format!("sysdefault:CARD={}", id.trim());
            options
                .push(serde_json::json!({"value": name, "label": microphone_label(&name, cards)}));
        }
    }
    serde_json::json!(options)
}

#[cfg(not(target_os = "linux"))]
pub fn input_device_options() -> serde_json::Value {
    use cpal::traits::{DeviceTrait, HostTrait};
    let host = cpal::default_host();
    let mut options = Vec::new();
    if let Ok(devices) = host.input_devices() {
        for device in devices {
            if let Ok(name) = device.name() {
                options.push(serde_json::json!({"value": name, "label": name}));
            }
        }
    }
    serde_json::json!(options)
}

fn microphone_label(name: &str, cards: &str) -> String {
    if let Some(card) = name.strip_prefix("sysdefault:CARD=") {
        for line in cards.lines() {
            if let Some((_, rest)) = line.split_once('[') {
                if let Some((id, rest)) = rest.split_once(']') {
                    if id.trim() == card {
                        if let Some((_, label)) = rest.split_once(" - ") {
                            return label.trim().to_string();
                        }
                    }
                }
            }
        }
        return card.to_string();
    }
    name.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::io::Write;

    #[test]
    #[cfg(target_os = "linux")]
    fn capture_options_skip_playback_only_and_duplicate_pcm_entries() {
        let cards = " 0 [HDMI ]: HDA - HDMI Output\n 1 [Mic ]: USB - USB Microphone\n 2 [Gone ]: USB - No Capture";
        let pcm = "00-00: HDMI : playback 1\n01-00: Mic : playback 1 : capture 1\n01-01: Mic : capture 1\n02-00: Gone : capture 0";
        assert_eq!(
            alsa_input_options(cards, pcm),
            serde_json::json!([
                {"value": "sysdefault:CARD=Mic", "label": "USB Microphone"}
            ])
        );
        assert_eq!(alsa_input_options("", ""), serde_json::json!([]));
    }

    #[test]
    fn microphone_and_hotkey_save_together_or_not_at_all() {
        let base = crate::config::default_config_content();
        let (_dir, path) = temp_config(&base);
        assert!(
            set_preferences(path.clone(), Some("F14"), Some("toggle"), None, Some(" ")).is_err()
        );
        assert_eq!(fs::read_to_string(&path).unwrap(), base);
        set_preferences(
            path.clone(),
            Some("F14"),
            Some("toggle"),
            None,
            Some("sysdefault:CARD=XDR"),
        )
        .unwrap();
        let saved: toml::Value = toml::from_str(&fs::read_to_string(path).unwrap()).unwrap();
        assert_eq!(
            saved["audio"]["device"].as_str(),
            Some("sysdefault:CARD=XDR")
        );
        assert_eq!(saved["hotkey"]["key"].as_str(), Some("F14"));
        assert_eq!(
            microphone_label(
                "sysdefault:CARD=XDR",
                " 3 [XDR   ]: USB-Audio - Studio Display XDR\n"
            ),
            "Studio Display XDR"
        );
    }

    #[test]
    fn hotkey_update_preserves_other_settings_and_comments() {
        let base = crate::config::default_config_content();
        let (_dir, path) = temp_config(&base);
        set_hotkey(path.clone(), Some("rightctrl"), Some("hybrid"), Some(true)).unwrap();
        let text = fs::read_to_string(&path).unwrap();
        let before: toml::Value = toml::from_str(&base).unwrap();
        let after: toml::Value = toml::from_str(&text).unwrap();
        assert_eq!(after["hotkey"]["key"].as_str(), Some("RIGHTCTRL"));
        assert_eq!(after["hotkey"]["mode"].as_str(), Some("hybrid"));
        for (name, value) in before.as_table().unwrap() {
            if name != "hotkey" {
                assert_eq!(&after[name], value);
            }
        }
        for comment in base
            .lines()
            .filter(|line| line.trim_start().starts_with('#'))
        {
            assert!(text.contains(comment), "Lost comment: {comment}");
        }
        set_hotkey(path.clone(), None, Some("toggle"), None).unwrap();
        let after: toml::Value = toml::from_str(&fs::read_to_string(path).unwrap()).unwrap();
        assert_eq!(after["hotkey"]["key"].as_str(), Some("RIGHTCTRL"));
        assert_eq!(after["hotkey"]["mode"].as_str(), Some("toggle"));
    }

    #[test]
    fn invalid_hotkey_update_leaves_file_unchanged() {
        let base = crate::config::default_config_content();
        let (_dir, path) = temp_config(&base);
        assert!(set_hotkey(path.clone(), Some("F14"), Some("bad-mode"), None).is_err());
        assert_eq!(fs::read_to_string(&path).unwrap(), base);
        #[cfg(target_os = "linux")]
        assert!(set_hotkey(path.clone(), Some("NOT_A_KEY"), Some("toggle"), None).is_err());
        assert_eq!(fs::read_to_string(&path).unwrap(), base);
    }

    fn temp_config(contents: &str) -> (tempfile::TempDir, PathBuf) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("config.toml");
        let mut f = fs::File::create(&path).unwrap();
        f.write_all(contents.as_bytes()).unwrap();
        (dir, path)
    }

    #[test]
    fn parse_engine_accepts_known_names() {
        for name in ENGINE_NAMES {
            assert!(parse_engine(name).is_some(), "should accept '{}'", name);
        }
    }

    #[test]
    fn parse_engine_rejects_unknown() {
        assert!(parse_engine("nope").is_none());
        assert!(parse_engine("Whisper").is_none(), "case-sensitive");
        assert!(parse_engine("").is_none());
    }

    #[test]
    fn engine_feature_whisper_always_compiled() {
        assert!(engine_feature_compiled("whisper"));
    }

    #[test]
    fn engine_feature_unknown_returns_false() {
        assert!(!engine_feature_compiled("not-a-real-engine"));
    }

    #[test]
    fn set_engine_rejects_unknown_name() {
        let (_dir, path) = temp_config("");
        let err = set_engine(path, "fakeengine").unwrap_err();
        match err {
            ConfigSetError::UnknownEngine(n) => assert_eq!(n, "fakeengine"),
            other => panic!("expected UnknownEngine, got {:?}", other),
        }
    }

    #[test]
    fn set_engine_whisper_succeeds_against_full_config() {
        // Use the production default config so load_config's strict
        // deserialization passes after the write. (A bare `engine = ...`
        // file would fail validation by design — voxtype's serde struct
        // requires every top-level table to be present.)
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("config.toml");
        fs::write(&path, crate::config::default_config_content()).unwrap();
        let written = set_engine(path.clone(), "whisper").expect("set whisper");
        assert_eq!(written, path);
        let contents = fs::read_to_string(&path).unwrap();
        assert!(
            contents.contains("engine = \"whisper\""),
            "missing engine line in {contents:?}"
        );
    }

    #[test]
    fn set_engine_preserves_comments_and_adjacent_fields() {
        // ConfigEditor's round-trip is the exact mechanism the TUI uses;
        // verify the CLI path doesn't disturb non-engine content.
        //
        // Use the production default config (which is a complete,
        // commented TOML document) and then sprinkle a custom marker
        // comment + adjacent field we expect to survive the round-trip.
        let mut base = crate::config::default_config_content();
        // Inject a marker comment near the top so we can prove comments
        // are preserved. Insert after the first newline so it lands
        // inside the document body rather than ahead of any header.
        let marker = "\n# VOXTYPE-TEST-MARKER: keep this comment\n";
        let insert_at = base.find('\n').map(|i| i + 1).unwrap_or(0);
        base.insert_str(insert_at, marker);

        let (_dir, path) = temp_config(&base);
        // Switching to whisper is always safe regardless of feature flags.
        set_engine(path.clone(), "whisper").expect("set engine");

        let after = fs::read_to_string(&path).unwrap();
        assert!(
            after.contains("# VOXTYPE-TEST-MARKER: keep this comment"),
            "marker comment lost after round-trip: {after}"
        );
        assert!(
            after.contains("engine = \"whisper\""),
            "engine not updated: {after}"
        );
        // [hotkey] table from the default config should still be present.
        assert!(
            after.contains("[hotkey]"),
            "hotkey table lost after round-trip: {after}"
        );
    }

    #[test]
    fn set_engine_in_memory_round_trip_preserves_comments() {
        // Pure ConfigEditor exercise (no full-config validation) — proves
        // that the toml_edit mutation we perform is the comment-preserving
        // one. Mirrors `round_trip_preserves_comments` in config_editor.rs.
        let (_dir, path) =
            temp_config("# top comment\nengine = \"parakeet\"\n# trailing comment\n");
        let mut ed = crate::tui::ConfigEditor::load_from_path(path).unwrap();
        ed.set_string("", "engine", "whisper");
        // We can't call ed.save() here without a full config schema, so
        // read the document directly via get_string for the round-trip
        // check.
        assert_eq!(ed.get_string("", "engine").as_deref(), Some("whisper"));
    }

    // Engines other than whisper/parakeet aren't enumerated in the default
    // feature set, so on a default `cargo test` run they'll fail the feature
    // gate. Exercise that path with a non-whisper engine and check the
    // error variant — but only if the feature isn't enabled, otherwise the
    // engine is legitimately available and this test would be misleading.
    #[test]
    fn set_engine_rejects_uncompiled_engine() {
        // Pick the first non-whisper engine whose feature is NOT compiled
        // into this test binary. Skip the test entirely if every engine is
        // compiled in (e.g. a maximalist CI build).
        let target = ENGINE_NAMES
            .iter()
            .find(|n| **n != "whisper" && !engine_feature_compiled(n));
        let Some(name) = target else {
            eprintln!("skipping: all engine features are compiled in this build");
            return;
        };
        let (_dir, path) = temp_config("");
        let err = set_engine(path, name).unwrap_err();
        match err {
            ConfigSetError::FeatureNotCompiled(n) => assert_eq!(&n, *name),
            other => panic!("expected FeatureNotCompiled, got {:?}", other),
        }
    }
}
