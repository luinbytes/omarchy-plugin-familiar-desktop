use familiar_desktop::{
    Result,
    caps_lock::{self, Paths},
    common::Hypr,
};
use std::{
    fs,
    os::unix::fs::{PermissionsExt, symlink},
    process::Command,
};

#[derive(Default)]
struct FakeHypr {
    calls: Vec<Vec<String>>,
    fail_reload: bool,
    config_error: bool,
    fail_probe: bool,
    config_errors_json: Option<String>,
}
impl Hypr for FakeHypr {
    fn command(&mut self, args: &[&str]) -> Result<String> {
        self.calls
            .push(args.iter().map(|s| s.to_string()).collect());
        if args == ["reload"] && self.fail_reload {
            self.fail_reload = false;
            return Err("fixture reload failure".into());
        }
        if args.first() == Some(&"eval") && self.fail_probe {
            return Err("unsupported Lua API".into());
        }
        if args == ["-j", "configerrors"] {
            if self.config_error {
                self.config_error = false;
                return Ok("[\"fixture parse error\"]".into());
            }
            return Ok(self
                .config_errors_json
                .clone()
                .unwrap_or_else(|| "[\"\"]".into()));
        }
        Ok("ok".into())
    }
}
fn fixture() -> (tempfile::TempDir, Paths) {
    let dir = tempfile::tempdir().unwrap();
    let paths = Paths {
        config: dir.path().join("hyprland.lua"),
        manifest: dir.path().join("plugin 'quoted'/manifest.json"),
        state: dir.path().join("state"),
        generated: dir.path().join("familiar-input/caps-lock.lua"),
    };
    fs::write(&paths.config, "-- personal config\nrequire('hypr.input')\n").unwrap();
    fs::set_permissions(&paths.config, fs::Permissions::from_mode(0o640)).unwrap();
    fs::create_dir_all(paths.manifest.parent().unwrap()).unwrap();
    fs::write(&paths.manifest, "{}").unwrap();
    (dir, paths)
}

#[test]
fn status_and_invalid_requests_never_mutate_or_reload() {
    let (_dir, p) = fixture();
    let before = fs::read(&p.config).unwrap();
    let mut h = FakeHypr::default();
    assert_eq!(
        caps_lock::change("status", &p, &mut h).unwrap()["mode"],
        "reset"
    );
    assert!(!p.state.exists());
    assert!(caps_lock::change("bad", &p, &mut h).is_err());
    assert_eq!(fs::read(&p.config).unwrap(), before);
    assert!(h.calls.is_empty());
}

#[test]
fn choices_persist_preserve_personal_content_and_reset_exactly() {
    let (_dir, p) = fixture();
    let before = fs::read_to_string(&p.config).unwrap();
    let input = p.config.with_file_name("input.lua");
    fs::write(&input, "-- custom UK keyboard and AltGr").unwrap();
    let mut h = FakeHypr::default();
    for mode in ["normal", "normal", "compose", "compose"] {
        let result = caps_lock::change(mode, &p, &mut h).unwrap();
        assert_eq!(result["mode"], mode);
        let current = fs::read_to_string(&p.config).unwrap();
        assert_eq!(
            caps_lock::split_current(&current, &p).unwrap(),
            (before.clone(), mode.into())
        );
        assert_eq!(
            fs::metadata(&p.config).unwrap().permissions().mode() & 0o777,
            0o640
        );
        assert_eq!(
            caps_lock::change("status", &p, &mut h).unwrap()["mode"],
            mode
        );
    }
    caps_lock::change("reset", &p, &mut h).unwrap();
    caps_lock::change("reset", &p, &mut h).unwrap();
    assert_eq!(fs::read_to_string(&p.config).unwrap(), before);
    assert_eq!(
        fs::read_to_string(input).unwrap(),
        "-- custom UK keyboard and AltGr"
    );
}

#[test]
fn caps_lock_coexists_with_command_and_resize_preferences() {
    use familiar_desktop::{input_preferences, window_mode};
    for caps_first in [false, true] {
        let (_dir, p) = fixture();
        let original = fs::read_to_string(&p.config).unwrap();
        let mut h = FakeHypr::default();
        if caps_first {
            caps_lock::change("normal", &p, &mut h).unwrap();
        }
        let mut other_paths = Vec::new();
        for kind in ["command", "resize"] {
            let other = window_mode::Paths {
                config: p.config.clone(),
                manifest: p.manifest.clone(),
                state: p.state.with_file_name(kind),
                generated: p.generated.with_file_name(format!("{kind}.lua")),
            };
            input_preferences::change(kind, "enable", &other, &mut h).unwrap();
            other_paths.push((kind, other));
        }
        if !caps_first {
            caps_lock::change("normal", &p, &mut h).unwrap();
        }
        assert_eq!(
            caps_lock::change("status", &p, &mut h).unwrap()["mode"],
            "normal"
        );
        caps_lock::change("compose", &p, &mut h).unwrap();
        caps_lock::change("reset", &p, &mut h).unwrap();
        let expected = other_paths
            .iter()
            .fold(original.clone(), |text, (kind, other)| {
                text + &input_preferences::include(kind, other)
            });
        assert_eq!(fs::read_to_string(&p.config).unwrap(), expected);
        assert!(!p.generated.exists());
        for (kind, other) in other_paths {
            assert_eq!(
                fs::read_to_string(&other.generated).unwrap(),
                input_preferences::hook(kind, &p.manifest).unwrap()
            );
            input_preferences::change(kind, "reset", &other, &mut h).unwrap();
        }
        assert_eq!(fs::read_to_string(&p.config).unwrap(), original);
    }
}

#[test]
fn reset_preserves_later_user_edits_and_handles_no_trailing_newline() {
    let (_dir, p) = fixture();
    fs::write(&p.config, "-- no trailing newline").unwrap();
    let mut h = FakeHypr::default();
    caps_lock::change("normal", &p, &mut h).unwrap();
    let mut text = fs::read_to_string(&p.config).unwrap();
    text.push_str("\n-- later personal change\n");
    fs::write(&p.config, text).unwrap();
    caps_lock::change("reset", &p, &mut h).unwrap();
    assert_eq!(
        fs::read_to_string(&p.config).unwrap(),
        "-- no trailing newline\n-- later personal change\n"
    );
}

#[test]
fn reload_or_configuration_failure_restores_previous_choice() {
    for config_error in [false, true] {
        let (_dir, p) = fixture();
        let mut h = FakeHypr::default();
        caps_lock::change("normal", &p, &mut h).unwrap();
        let before = fs::read(&p.config).unwrap();
        h.fail_reload = !config_error;
        h.config_error = config_error;
        assert!(
            caps_lock::change("compose", &p, &mut h)
                .unwrap_err()
                .contains("Previous configuration restored")
        );
        assert_eq!(fs::read(&p.config).unwrap(), before);
        assert_eq!(
            caps_lock::change("status", &p, &mut h).unwrap()["mode"],
            "normal"
        );
    }
}

#[test]
fn damaged_foreign_or_edited_blocks_are_not_overwritten() {
    let (_dir, p) = fixture();
    let block = caps_lock::hook("normal", &p.manifest).unwrap();
    let variants = [
        block.replace("-- END FAMILIAR CAPS LOCK\n", ""),
        block.repeat(2),
        block.replace("caps:capslock", "caps:escape"),
        caps_lock::hook("normal", &p.manifest.with_file_name("other.json")).unwrap(),
    ];
    for content in variants {
        fs::write(&p.config, &content).unwrap();
        let mut h = FakeHypr::default();
        assert!(caps_lock::change("reset", &p, &mut h).is_err());
        assert_eq!(fs::read_to_string(&p.config).unwrap(), content);
        assert!(h.calls.is_empty());
    }
}

#[test]
fn missing_symlink_and_nonregular_config_fail_closed() {
    let (_dir, p) = fixture();
    fs::remove_file(&p.config).unwrap();
    let mut h = FakeHypr::default();
    assert!(caps_lock::change("normal", &p, &mut h).is_err());
    symlink("missing-target", &p.config).unwrap();
    assert!(caps_lock::change("normal", &p, &mut h).is_err());
    assert!(
        fs::symlink_metadata(&p.config)
            .unwrap()
            .file_type()
            .is_symlink()
    );
    fs::remove_file(&p.config).unwrap();
    fs::create_dir(&p.config).unwrap();
    assert!(caps_lock::change("normal", &p, &mut h).is_err());
    assert!(h.calls.is_empty());
}

#[test]
fn incompatible_compositor_keeps_config_unchanged() {
    let (_dir, p) = fixture();
    let before = fs::read(&p.config).unwrap();
    let mut h = FakeHypr {
        fail_probe: true,
        ..Default::default()
    };
    assert!(caps_lock::change("normal", &p, &mut h).is_err());
    assert_eq!(fs::read(&p.config).unwrap(), before);
}

#[test]
fn generated_lua_preserves_altgr_other_compose_and_layout_options() {
    let (dir, p) = fixture();
    // Execute the actual generated hook, not a second implementation of its filter.
    for (mode, wanted) in [("normal", "caps:capslock"), ("compose", "compose:caps")] {
        let hook = dir.path().join("hook.lua");
        fs::write(&hook, caps_lock::hook(mode, &p.manifest).unwrap()).unwrap();
        let harness = dir.path().join("check.lua");
        let script = format!(
            r#"
local hook = {}
for _, fixture in ipairs({{
  {{"compose:caps,shift:both_capslock_cancel,grp:alts_toggle,lv3:ralt_switch", "grp:alts_toggle,lv3:ralt_switch,{wanted}"}},
  {{"ctrl:nocaps,compose:rctrl,grp:caps_toggle", "compose:rctrl,{wanted}"}},
  {{"caps:escape, grp:alt_shift_toggle ", "grp:alt_shift_toggle,{wanted}"}},
  {{"", "{wanted}"}}
}}) do
  local actual = fixture[1]
  hl = {{ get_config = function(key) assert(key == "input.kb_options"); return actual end,
    config = function(value) actual = value.input.kb_options end }}
  dofile(hook)
  assert(actual == fixture[2], actual)
  dofile(hook)
  assert(actual == fixture[2], "repeated reload changed options")
end
-- A removed plugin must not leave an active keyboard override.
io.open = function() return nil end
hl = {{ get_config = function() error("removed plugin read config") end,
  config = function() error("removed plugin changed config") end }}
dofile(hook)
"#,
            familiar_desktop::common::lua(&hook.to_string_lossy())
        );
        fs::write(&harness, script).unwrap();
        let output = Command::new("lua")
            .arg(&harness)
            .output()
            .expect("Install Lua for development tests");
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
}

#[test]
fn separate_choice_changes_do_not_rewrite_hyprland_and_reset_removes_include() {
    let (_dir, p) = fixture();
    let original = fs::read(&p.config).unwrap();
    let mut h = FakeHypr::default();
    caps_lock::change("normal", &p, &mut h).unwrap();
    let included = fs::read(&p.config).unwrap();
    assert!(!String::from_utf8_lossy(&included).contains("caps:capslock"));
    assert!(
        fs::read_to_string(&p.generated)
            .unwrap()
            .contains("caps:capslock")
    );
    caps_lock::change("compose", &p, &mut h).unwrap();
    assert_eq!(fs::read(&p.config).unwrap(), included);
    assert!(
        fs::read_to_string(&p.generated)
            .unwrap()
            .contains("compose:caps")
    );
    caps_lock::change("reset", &p, &mut h).unwrap();
    assert_eq!(fs::read(&p.config).unwrap(), original);
    assert!(!p.generated.exists());
}

#[test]
fn legacy_inline_preference_migrates_without_losing_user_bytes() {
    let (_dir, p) = fixture();
    let original = fs::read_to_string(&p.config).unwrap();
    fs::write(
        &p.config,
        format!(
            "{}{}",
            original,
            caps_lock::hook("normal", &p.manifest).unwrap()
        ),
    )
    .unwrap();
    let mut h = FakeHypr::default();
    assert_eq!(
        caps_lock::change("status", &p, &mut h).unwrap()["mode"],
        "normal"
    );
    caps_lock::change("compose", &p, &mut h).unwrap();
    assert!(
        !fs::read_to_string(&p.config)
            .unwrap()
            .contains("-- BEGIN FAMILIAR CAPS LOCK")
    );
    caps_lock::change("reset", &p, &mut h).unwrap();
    assert_eq!(fs::read_to_string(&p.config).unwrap(), original);
}

#[test]
fn failed_change_restores_both_files_and_failed_first_apply_removes_generated_file() {
    let (_dir, p) = fixture();
    let original = fs::read(&p.config).unwrap();
    let mut h = FakeHypr {
        fail_reload: true,
        ..Default::default()
    };
    assert!(caps_lock::change("normal", &p, &mut h).is_err());
    assert_eq!(fs::read(&p.config).unwrap(), original);
    assert!(!p.generated.exists());
    caps_lock::change("normal", &p, &mut h).unwrap();
    let generated = fs::read(&p.generated).unwrap();
    h.fail_reload = true;
    assert!(caps_lock::change("compose", &p, &mut h).is_err());
    assert_eq!(fs::read(&p.generated).unwrap(), generated);
}

#[test]
fn edited_or_symlinked_separate_config_and_include_are_preserved() {
    let (_dir, p) = fixture();
    let mut h = FakeHypr::default();
    caps_lock::change("normal", &p, &mut h).unwrap();
    let main = fs::read(&p.config).unwrap();
    fs::write(&p.generated, "-- personal edit").unwrap();
    assert!(caps_lock::change("reset", &p, &mut h).is_err());
    assert_eq!(fs::read(&p.config).unwrap(), main);
    assert_eq!(
        fs::read_to_string(&p.generated).unwrap(),
        "-- personal edit"
    );
    fs::remove_file(&p.generated).unwrap();
    symlink(&p.config, &p.generated).unwrap();
    assert!(caps_lock::change("compose", &p, &mut h).is_err());
    fs::remove_file(&p.generated).unwrap();
    fs::write(
        &p.config,
        String::from_utf8(main).unwrap().replace("dofile", "print"),
    )
    .unwrap();
    assert!(caps_lock::change("normal", &p, &mut h).is_err());
}

#[test]
fn separate_include_executes_and_is_inert_without_plugin_or_generated_file() {
    let (dir, p) = fixture();
    fs::create_dir_all(p.generated.parent().unwrap()).unwrap();
    fs::write(&p.generated, "loaded = (loaded or 0) + 1").unwrap();
    let harness = dir.path().join("include.lua");
    let include = caps_lock::include_hook(&p);
    let script = format!(
        "loaded = 0\n{include}\nassert(loaded == 1)\nos.remove({})\n{include}\nassert(loaded == 1)\nio.open = function() return nil end\n{include}\nassert(loaded == 1)",
        familiar_desktop::common::lua(&p.generated.to_string_lossy())
    );
    fs::write(&harness, script).unwrap();
    let output = Command::new("lua")
        .arg(&harness)
        .output()
        .expect("Install Lua for development tests");
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

// Keep an independently frozen copy of the loop emitted by rc.2.
fn old_hook(mode: &str, manifest: &std::path::Path) -> String {
    caps_lock::hook(mode, manifest)
        .unwrap()
        .replace("for raw_option in", "for option in")
        .replace("local option = raw_option:match", "option = option:match")
}

#[test]
fn rc2_inline_and_separate_config_upgrade_and_reset_preserve_personal_edits() {
    for separate in [false, true] {
        for mode in ["normal", "compose"] {
            for action in ["normal", "compose", "reset"] {
                let (_dir, p) = fixture();
                let original = fs::read_to_string(&p.config).unwrap();
                let old = old_hook(mode, &p.manifest);
                let included = if separate {
                    fs::create_dir_all(p.generated.parent().unwrap()).unwrap();
                    fs::write(&p.generated, &old).unwrap();
                    caps_lock::include_hook(&p)
                } else {
                    old
                };
                let personal = "\n-- later personal edit\n";
                fs::write(&p.config, format!("{original}{included}{personal}")).unwrap();
                let mut h = FakeHypr::default();
                assert_eq!(
                    caps_lock::change("status", &p, &mut h).unwrap()["mode"],
                    mode
                );
                caps_lock::change(action, &p, &mut h).unwrap();
                if action != "reset" {
                    assert_eq!(
                        fs::read_to_string(&p.generated).unwrap(),
                        caps_lock::hook(action, &p.manifest).unwrap()
                    );
                }
                caps_lock::change("reset", &p, &mut h).unwrap();
                assert_eq!(
                    fs::read_to_string(&p.config).unwrap(),
                    format!("{original}{personal}")
                );
                assert!(!p.generated.exists());
            }
        }
    }
}

#[test]
fn edited_rc2_generated_config_is_not_adopted() {
    let (_dir, p) = fixture();
    fs::create_dir_all(p.generated.parent().unwrap()).unwrap();
    let old = old_hook("normal", &p.manifest) + "-- personal edit\n";
    fs::write(&p.generated, &old).unwrap();
    let before = fs::read(&p.config).unwrap();
    assert!(caps_lock::change("normal", &p, &mut FakeHypr::default()).is_err());
    assert_eq!(fs::read_to_string(&p.generated).unwrap(), old);
    assert_eq!(fs::read(&p.config).unwrap(), before);
}

#[test]
fn empty_error_entries_allow_apply_and_reset_but_real_or_malformed_errors_rollback() {
    for response in [r#"[]"#, r#"[""]"#, r#"["", "  ", "\n\t"]"#] {
        let (_dir, p) = fixture();
        let before = fs::read(&p.config).unwrap();
        let mut h = FakeHypr {
            config_errors_json: Some(response.into()),
            ..Default::default()
        };
        for mode in ["normal", "compose", "reset"] {
            caps_lock::change(mode, &p, &mut h).unwrap();
        }
        assert_eq!(fs::read(&p.config).unwrap(), before);
        assert!(!p.generated.exists());
    }
    for response in [
        r#"["", "real parse error", " "]"#,
        r#"[null]"#,
        r#"{}"#,
        "not json",
    ] {
        let (_dir, p) = fixture();
        let before = fs::read(&p.config).unwrap();
        let mut h = FakeHypr {
            config_errors_json: Some(response.into()),
            ..Default::default()
        };
        let error = caps_lock::change("normal", &p, &mut h).unwrap_err();
        if response.contains("real parse error") {
            assert!(error.contains("real parse error"));
        }
        assert_eq!(fs::read(&p.config).unwrap(), before);
        assert!(!p.generated.exists());
    }
}
