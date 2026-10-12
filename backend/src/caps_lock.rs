//! Explicit, reversible keyboard preference. Never rewrite input.lua or core files.
use crate::config_file::{self, GeneratedUpdate, read as text};
use crate::{
    Result,
    common::{self, Hypr, checked},
};
use serde_json::{Value, json};
use std::{
    fs,
    path::{Path, PathBuf},
};

const BEGIN: &str = "\n-- BEGIN FAMILIAR CAPS LOCK\n";
const END: &str = "-- END FAMILIAR CAPS LOCK\n";

pub struct Paths {
    pub config: PathBuf,
    pub manifest: PathBuf,
    pub state: PathBuf,
    pub generated: PathBuf,
}

impl Paths {
    pub fn system() -> Result<Self> {
        let binary = std::env::current_exe().map_err(|e| e.to_string())?;
        let source = binary
            .parent()
            .and_then(Path::parent)
            .ok_or("Install the helper in the plugin bin directory")?;
        let state = std::env::var_os("XDG_STATE_HOME")
            .map(PathBuf::from)
            .unwrap_or(common::home()?.join(".local/state"));
        Ok(Self {
            config: common::config_home()?.join("hypr/hyprland.lua"),
            manifest: source.join("manifest.json"),
            state: state.join("omarchy/familiar-caps-lock"),
            generated: common::config_home()?.join("omarchy/familiar-input/caps-lock.lua"),
        })
    }
}

pub fn hook(mode: &str, manifest: &Path) -> Result<String> {
    let option = match mode {
        "normal" => "caps:capslock",
        "compose" => "compose:caps",
        _ => return Err("Choose normal, compose or reset".into()),
    };
    Ok(format!(
        "{BEGIN}-- mode: {mode}\ndo\n  local plugin = io.open({}, \"r\")\n  if plugin then\n    plugin:close()\n    local options = {{}}\n    for raw_option in (hl.get_config(\"input.kb_options\") or \"\"):gmatch(\"[^,]+\") do\n      local option = raw_option:match(\"^%s*(.-)%s*$\")\n      if not option:find(\"caps\", 1, true) then\n        table.insert(options, option)\n      end\n    end\n    table.insert(options, \"{option}\")\n    hl.config({{ input = {{ kb_options = table.concat(options, \",\") }} }})\n  end\nend\n{END}",
        common::lua(&manifest.to_string_lossy())
    ))
}

// Recognise the exact pre-rc.3 template for migration/removal, never execute it.
fn legacy_hook(mode: &str, manifest: &Path) -> Result<String> {
    Ok(hook(mode, manifest)?
        .replace("for raw_option in", "for option in")
        .replace("local option = raw_option:match", "option = option:match"))
}

// Only this stable, guarded include lives in the user's main configuration.
pub fn include_hook(paths: &Paths) -> String {
    format!(
        "\n-- BEGIN FAMILIAR INPUT\ndo\n  local plugin = io.open({}, 'r')\n  if plugin then\n    plugin:close()\n    local config = io.open({}, 'r')\n    if config then config:close(); dofile({}) end\n  end\nend\n-- END FAMILIAR INPUT\n",
        common::lua(&paths.manifest.to_string_lossy()),
        common::lua(&paths.generated.to_string_lossy()),
        common::lua(&paths.generated.to_string_lossy())
    )
}

fn generated_content(paths: &Paths) -> Result<Option<String>> {
    match fs::symlink_metadata(&paths.generated) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.to_string()),
        Ok(_) => {
            let value = text(&paths.generated)?;
            if !["normal", "compose"].iter().any(|mode| {
                [
                    hook(mode, &paths.manifest),
                    legacy_hook(mode, &paths.manifest),
                ]
                .iter()
                .any(|candidate| candidate.as_ref().ok() == Some(&value))
            }) {
                return Err(
                    "Familiar's separate keyboard config was edited; no file changed".into(),
                );
            }
            Ok(Some(value))
        }
    }
}

pub fn split_current(value: &str, paths: &Paths) -> Result<(String, String)> {
    if config_file::has_marker(value, "-- BEGIN FAMILIAR INPUT")
        || config_file::has_marker(value, "-- END FAMILIAR INPUT")
    {
        let clean = crate::config_file::strip_exact(
            value,
            "-- BEGIN FAMILIAR INPUT",
            "-- END FAMILIAR INPUT",
            &include_hook(paths),
        )?;
        let (_, legacy) = split(&clean, &paths.manifest)?;
        if legacy != "reset" {
            return Err("Duplicate legacy and separate keyboard hooks; no file changed".into());
        }
        let mode = match generated_content(paths)? {
            Some(content) => split(&content, &paths.manifest)?.1,
            None => "reset".into(),
        };
        return Ok((clean, mode));
    }
    split(value, &paths.manifest)
}

pub fn split(text: &str, manifest: &Path) -> Result<(String, String)> {
    let starts = text.matches("-- BEGIN FAMILIAR CAPS LOCK").count();
    let ends = text.matches("-- END FAMILIAR CAPS LOCK").count();
    if starts == 0 && ends == 0 {
        return Ok((text.into(), "reset".into()));
    }
    if starts == 1 && ends == 1 {
        for mode in ["normal", "compose"] {
            for block in [hook(mode, manifest)?, legacy_hook(mode, manifest)?] {
                if let Some(start) = text.find(&block) {
                    return Ok((
                        format!("{}{}", &text[..start], &text[start + block.len()..]),
                        mode.into(),
                    ));
                }
            }
        }
    }
    Err("Familiar Caps Lock block was edited, damaged or belongs to another installation; no file changed".into())
}

pub fn change(mode: &str, paths: &Paths, hypr: &mut impl Hypr) -> Result<Value> {
    if !["normal", "compose", "reset", "status"].contains(&mode) {
        return Err("Usage: familiar-desktop caps-lock <normal|compose|reset|status>".into());
    }
    let _lock = if mode == "status" {
        None
    } else {
        Some(common::lock(&paths.state.join("config.lock"))?)
    };
    let before = text(&paths.config)?;
    let (clean, previous) = split_current(&before, paths)?;
    if mode == "status" {
        return Ok(
            json!({"state":"ok","mode":previous,"message":"Saved preference; per-device keyboard overrides still take precedence."}),
        );
    }
    let after = if mode == "reset" {
        clean
    } else {
        if !paths.manifest.is_file() {
            return Err("Familiar manifest is missing; no file changed".into());
        }
        // Refuse unsupported compositor APIs before touching the user's config.
        checked(
            hypr,
            &[
                "eval",
                "assert(hl and hl.config and hl.get_config, 'Familiar Caps Lock requires Hyprland Lua configuration')",
            ],
        )?;
        format!("{}{}", clean, include_hook(paths))
    };
    let generated_before = generated_content(paths)?;
    let generated_after = if mode == "reset" {
        None
    } else {
        Some(hook(mode, &paths.manifest)?)
    };
    let backup = config_file::apply_generated(
        hypr,
        GeneratedUpdate {
            config: &paths.config,
            generated: &paths.generated,
            backups: &paths.state,
            before: &before,
            after: &after,
            generated_before: generated_before.as_deref(),
            generated_after: generated_after.as_deref(),
        },
        |hypr| {
            if mode == "reset" {
                return Ok(());
            }
            let option = if mode == "normal" {
                "caps:capslock"
            } else {
                "compose:caps"
            };
            checked(
                hypr,
                &[
                    "eval",
                    &format!(
                        "assert((',' .. (hl.get_config('input.kb_options') or '') .. ','):find({}, 1, true), 'Caps Lock override did not apply')",
                        common::lua(&format!(",{option},"))
                    ),
                ],
            )
        },
    )?;
    Ok(
        json!({"state":"ok","mode":mode,"backup":backup,"message":if mode == "reset" { "Using your keyboard configuration again." } else { "Caps Lock preference applied. Per-device overrides still take precedence." }}),
    )
}

pub fn execute(args: &[String]) -> Result<Value> {
    if args.len() != 1 {
        return Err("Usage: familiar-desktop caps-lock <normal|compose|reset|status>".into());
    }
    change(&args[0], &Paths::system()?, &mut common::SystemHypr)
}
