//! Local dictation history for OmaType's desktop integrations.

use crate::config::Config;
use serde::{Deserialize, Serialize};
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use uuid::Uuid;

const MAX_HISTORY_ENTRIES: usize = 200;

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
pub struct HistoryEntry {
    pub id: String,
    pub timestamp: String,
    pub duration_secs: f32,
    pub mode: String,
    pub engine: String,
    pub model: String,
    pub text: String,
}

impl HistoryEntry {
    pub fn new(
        duration_secs: f32,
        mode: impl Into<String>,
        engine: impl Into<String>,
        model: impl Into<String>,
        text: impl Into<String>,
    ) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            timestamp: chrono::Utc::now().to_rfc3339(),
            duration_secs,
            mode: mode.into(),
            engine: engine.into(),
            model: model.into(),
            text: text.into(),
        }
    }
}

pub fn history_path() -> PathBuf {
    Config::data_dir().join("history.json")
}

pub fn add(entry: HistoryEntry) -> io::Result<()> {
    let path = history_path();
    let mut entries = load_from(&path)?;
    entries.insert(0, entry);
    entries.truncate(MAX_HISTORY_ENTRIES);
    save_to(&path, &entries)
}

pub fn list(limit: usize) -> io::Result<Vec<HistoryEntry>> {
    let mut entries = load_from(&history_path())?;
    entries.truncate(limit);
    Ok(entries)
}

pub fn find(id: &str) -> io::Result<Option<HistoryEntry>> {
    Ok(load_from(&history_path())?
        .into_iter()
        .find(|entry| entry.id == id || entry.id.starts_with(id)))
}

pub fn delete(id: &str) -> io::Result<bool> {
    let path = history_path();
    let mut entries = load_from(&path)?;
    let before = entries.len();
    entries.retain(|entry| entry.id != id && !entry.id.starts_with(id));
    if entries.len() == before {
        return Ok(false);
    }
    save_to(&path, &entries)?;
    Ok(true)
}

pub fn clear() -> io::Result<()> {
    save_to(&history_path(), &[])
}

fn load_from(path: &Path) -> io::Result<Vec<HistoryEntry>> {
    match fs::read(path) {
        Ok(bytes) => serde_json::from_slice(&bytes)
            .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(Vec::new()),
        Err(error) => Err(error),
    }
}

fn save_to(path: &Path, entries: &[HistoryEntry]) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    let temporary_path = path.with_extension(format!("{}.tmp", Uuid::new_v4()));
    let mut file = OpenOptions::new()
        .create_new(true)
        .write(true)
        .mode(0o600)
        .open(&temporary_path)?;
    serde_json::to_writer_pretty(&mut file, entries).map_err(io::Error::other)?;
    file.write_all(b"\n")?;
    file.sync_all()?;
    fs::rename(temporary_path, path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn entry(id: &str, text: &str) -> HistoryEntry {
        HistoryEntry {
            id: id.to_string(),
            timestamp: "2026-08-24T20:00:00Z".to_string(),
            duration_secs: 3.5,
            mode: "batch".to_string(),
            engine: "parakeet".to_string(),
            model: "parakeet-unified-en-0.6b-int8".to_string(),
            text: text.to_string(),
        }
    }

    #[test]
    fn history_round_trip_preserves_newest_first() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("history.json");
        let entries = vec![entry("new", "Newest"), entry("old", "Older")];

        save_to(&path, &entries).unwrap();

        assert_eq!(load_from(&path).unwrap(), entries);
        assert_eq!(
            fs::metadata(path).unwrap().permissions().mode() & 0o777,
            0o600
        );
    }

    #[test]
    fn missing_history_is_empty() {
        let directory = tempfile::tempdir().unwrap();
        assert!(load_from(&directory.path().join("missing.json"))
            .unwrap()
            .is_empty());
    }
}
