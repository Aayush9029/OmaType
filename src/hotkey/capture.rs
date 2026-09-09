//! Short-lived hotkey inhibition while the settings UI captures a key.
//! The OS releases the lock even if the UI or capture process crashes.
use crate::config::Config;
use std::fs::{File, OpenOptions};
use std::os::fd::AsRawFd;
use std::path::Path;

fn lock_at(path: &Path) -> std::io::Result<File> {
    let file = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(path)?;
    if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(file)
}

pub(super) fn inhibit() -> std::io::Result<File> {
    std::fs::create_dir_all(Config::runtime_dir())?;
    lock_at(&Config::runtime_dir().join("hotkey-capture.lock"))
}

fn locked_at(path: &Path) -> bool {
    let Ok(file) = File::open(path) else {
        return false;
    };
    let result = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
    result != 0 && std::io::Error::last_os_error().raw_os_error() == Some(libc::EWOULDBLOCK)
}

pub fn active() -> bool {
    locked_at(&Config::runtime_dir().join("hotkey-capture.lock"))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn capture_inhibits_only_while_owner_is_alive() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("capture.lock");
        assert!(!locked_at(&path));
        let owner = lock_at(&path).unwrap();
        assert!(locked_at(&path));
        assert!(lock_at(&path).is_err());
        drop(owner);
        assert!(!locked_at(&path));
        assert!(lock_at(&path).is_ok());
    }
}
