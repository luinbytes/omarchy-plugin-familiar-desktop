//! Surgical edits to user-owned configuration. Never restore an old whole-file
//! backup over subsequent user edits.
use crate::{Result, common};
use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
};

pub fn read(path: &Path) -> Result<String> {
    let metadata = fs::symlink_metadata(path).map_err(|e| e.to_string())?;
    if !metadata.file_type().is_file() {
        return Err("Configuration must be a regular file, not a symlink; no file changed".into());
    }
    String::from_utf8(common::bounded_file(path, common::FILE_LIMIT)?).map_err(|e| e.to_string())
}

pub fn replace(
    path: &Path,
    expected: &str,
    replacement: &str,
    backups: &Path,
) -> Result<Option<PathBuf>> {
    if read(path)? != expected {
        return Err(
            "Configuration changed externally; no file changed. Retry after reviewing your edits"
                .into(),
        );
    }
    if expected == replacement {
        return Ok(None);
    }
    let permissions = fs::metadata(path).map_err(|e| e.to_string())?.permissions();
    fs::create_dir_all(backups).map_err(|e| e.to_string())?;
    let mut backup = tempfile::Builder::new()
        .prefix("before-")
        .suffix(".lua")
        .tempfile_in(backups)
        .map_err(|e| e.to_string())?;
    backup
        .write_all(expected.as_bytes())
        .map_err(|e| e.to_string())?;
    backup.as_file().sync_all().map_err(|e| e.to_string())?;
    let (_, backup_path) = backup.keep().map_err(|e| e.to_string())?;
    let mut temp =
        tempfile::NamedTempFile::new_in(path.parent().ok_or("Missing config directory")?)
            .map_err(|e| e.to_string())?;
    temp.write_all(replacement.as_bytes())
        .map_err(|e| e.to_string())?;
    temp.as_file()
        .set_permissions(permissions)
        .map_err(|e| e.to_string())?;
    temp.as_file().sync_all().map_err(|e| e.to_string())?;
    if read(path)? != expected {
        return Err("Configuration changed externally; no file changed".into());
    }
    temp.persist(path).map_err(|e| e.to_string())?;
    Ok(Some(backup_path))
}

// Marker namespaces can overlap (INPUT, INPUT command, INPUT resize).
// Count complete marker lines so one preference cannot claim another's hook.
pub fn has_marker(text: &str, marker: &str) -> bool {
    text.lines().any(|line| line.trim() == marker)
}

pub fn strip_exact(text: &str, begin: &str, end: &str, block: &str) -> Result<String> {
    let starts = text.lines().filter(|line| line.trim() == begin).count();
    let ends = text.lines().filter(|line| line.trim() == end).count();
    if starts == 0 && ends == 0 {
        return Ok(text.into());
    }
    if starts == 1
        && ends == 1
        && let Some(offset) = text.find(block)
    {
        return Ok(format!(
            "{}{}",
            &text[..offset],
            &text[offset + block.len()..]
        ));
    }
    Err(
        "Familiar hook was edited, damaged or belongs to another installation; no file changed"
            .into(),
    )
}

/// Files and expected bytes prepared by a feature after its ownership checks.
/// `generated_after = None` means reset: remove the owned file after reload.
pub struct GeneratedUpdate<'a> {
    pub config: &'a Path,
    pub generated: &'a Path,
    pub backups: &'a Path,
    pub before: &'a str,
    pub after: &'a str,
    pub generated_before: Option<&'a str>,
    pub generated_after: Option<&'a str>,
}

fn replace_generated(path: &Path, expected: Option<&str>, replacement: Option<&str>) -> Result<()> {
    let current = match fs::symlink_metadata(path) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
        Err(e) => return Err(e.to_string()),
        Ok(_) => Some(read(path)?),
    };
    if current.as_deref() != expected {
        return Err(
            "Separate Familiar config changed externally; preserve it and review the backup".into(),
        );
    }
    match replacement {
        Some(value) => common::atomic(path, value.as_bytes()),
        None if current.is_some() => fs::remove_file(path).map_err(|e| e.to_string()),
        None => Ok(()),
    }
}

pub fn reload(hypr: &mut impl common::Hypr) -> Result<()> {
    common::checked(hypr, &["reload"])?;
    let errors: Vec<String> = serde_json::from_str(&hypr.command(&["-j", "configerrors"])?)
        .map_err(|_| "Could not verify Hyprland configuration errors")?;
    // Hyprland can report [""] for no errors. Ignore only blank entries.
    let errors: Vec<&str> = errors
        .iter()
        .map(|e| e.trim())
        .filter(|e| !e.is_empty())
        .collect();
    if errors.is_empty() {
        return Ok(());
    }
    Err(format!(
        "Hyprland configuration error: {}",
        common::clipped(&errors.join("; "))
    ))
}

/// Write, reload and verify as one reversible operation. Never roll back over
/// external edits. Feature modules retain parsing, migration and Lua generation.
pub fn apply_generated<H: common::Hypr>(
    hypr: &mut H,
    update: GeneratedUpdate<'_>,
    verify: impl FnOnce(&mut H) -> Result<()>,
) -> Result<Option<PathBuf>> {
    let GeneratedUpdate {
        config,
        generated,
        backups,
        before,
        after,
        generated_before,
        generated_after,
    } = update;
    if let Some(content) = generated_after {
        replace_generated(generated, generated_before, Some(content))?;
    }
    let backup = match replace(config, before, after, backups) {
        Ok(backup) => backup,
        Err(error) => {
            if generated_after.is_some() {
                replace_generated(generated, generated_after, generated_before)?;
            }
            return Err(error);
        }
    };
    if let Err(error) = reload(hypr).and_then(|()| verify(hypr)) {
        if read(config)? != after {
            return Err(format!(
                "{error}. Config changed externally; preserve your edits and recover from {backup:?}"
            ));
        }
        if generated_after.is_some() {
            replace_generated(generated, generated_after, generated_before)?;
        }
        replace(config, after, before, backups)?;
        let recovery = reload(hypr);
        return Err(format!(
            "{error}. Previous configuration restored on disk. Recovery reload: {}",
            recovery.err().unwrap_or_else(|| "ok".into())
        ));
    }
    if generated_after.is_none() {
        replace_generated(generated, generated_before, None)?;
    }
    Ok(backup)
}
