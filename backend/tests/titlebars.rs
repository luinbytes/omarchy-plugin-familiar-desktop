use familiar_desktop::{
    Result,
    common::{self, Hypr},
    titlebars::{self, Args, BEGIN, Paths},
};
use serde_json::{Value, json};
use std::{fs, path::PathBuf};
struct Fake {
    paths: Paths,
    loaded: bool,
    errors: String,
    fail_reload: bool,
    load_on_reload: bool,
    probe_ok: bool,
    calls: Vec<Vec<String>>,
}
impl Hypr for Fake {
    fn command(&mut self, args: &[&str]) -> Result<String> {
        self.calls
            .push(args.iter().map(|s| s.to_string()).collect());
        if args == ["-j", "plugin", "list"] {
            return Ok(if self.loaded {
                json!([{"name":"hyprbars"}])
            } else {
                json!([])
            }
            .to_string());
        }
        if args.starts_with(&["plugin", "load"]) {
            self.loaded = true;
        }
        if args.starts_with(&["plugin", "unload"]) {
            self.loaded = false;
        }
        if args == ["reload"] {
            if self.fail_reload {
                return Ok("error: reload rejected".into());
            }
            self.loaded = fs::read_to_string(self.paths.directory.join("titlebars.lua"))
                .unwrap_or_default()
                .contains("hl.plugin.load")
                && self.load_on_reload
                && fs::read_to_string(&self.paths.config)
                    .unwrap_or_default()
                    .contains(BEGIN);
        }
        if args.first() == Some(&"eval") && !self.probe_ok {
            return Ok("error: missing Lua support".into());
        }
        if args == ["-j", "configerrors"] {
            return Ok(json!([self.errors]).to_string());
        }
        if args == ["configerrors"] {
            return Ok(self.errors.clone());
        }
        Ok("ok".into())
    }
}
struct Fixture {
    _temp: tempfile::TempDir,
    paths: Paths,
    args: Args,
    hypr: Fake,
    original: String,
}
impl Fixture {
    fn new() -> Self {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().to_path_buf();
        let paths = Paths {
            home: root.clone(),
            source: root.join("plugin"),
            binary: root.join("plugin/bin/familiar-desktop"),
            directory: root.join("titlebars"),
            config: root.join("looknfeel.lua"),
            official_library: root.join("system/titlebars.so"),
            compositor_session: "session-before".into(),
        };
        fs::create_dir_all(&paths.directory).unwrap();
        fs::create_dir_all(&paths.source).unwrap();
        fs::write(paths.source.join("manifest.json"), "{}").unwrap();
        let library = paths.source.join("bin/hyprbars/test-abi/hyprbars.so");
        fs::create_dir_all(library.parent().unwrap()).unwrap();
        fs::write(&library, "").unwrap();
        let original =
            "-- personal overrides\nhl.config({ decoration = { rounding = 9 } })\n".to_string();
        fs::write(&paths.config, &original).unwrap();
        let args = Args {
            owner: "200-new".into(),
            library: Some(library),
            ..Args::default()
        };
        let hypr = Fake {
            paths: paths.clone(),
            loaded: false,
            errors: String::new(),
            fail_reload: false,
            load_on_reload: true,
            probe_ok: true,
            calls: Vec::new(),
        };
        Self {
            _temp: temp,
            paths,
            args,
            hypr,
            original,
        }
    }
    fn setup(&mut self) -> Result<Value> {
        titlebars::setup(&self.args, &self.paths, &mut self.hypr)
    }
    fn apply(&mut self) -> Result<Value> {
        titlebars::reconcile(&self.args, &self.paths, &mut self.hypr)
    }
    fn generated(&self) -> String {
        fs::read_to_string(self.paths.directory.join("titlebars.lua")).unwrap()
    }
    fn theme(&self, v: Value) {
        let path = self
            .paths
            .home
            .join(".local/state/omarchy/current/theme/familiar-desktop.json");
        common::atomic(&path, v.to_string().as_bytes()).unwrap();
    }
}
#[test]
fn missing_dependency_preserves_personal_config() {
    let mut f = Fixture::new();
    assert_eq!(f.apply().unwrap()["state"], "setup-required");
    assert_eq!(fs::read_to_string(&f.paths.config).unwrap(), f.original);
}
#[test]
fn setup_idempotent_and_remove_preserves_overrides() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    f.setup().unwrap();
    let text = fs::read_to_string(&f.paths.config).unwrap();
    assert_eq!(text.matches(BEGIN).count(), 1);
    assert_eq!(
        titlebars::strip_hook(&text).unwrap().trim_end(),
        f.original.trim_end()
    );
    assert!(!f.hypr.loaded);
    titlebars::remove(&f.paths, &mut f.hypr).unwrap();
    assert!(!f.paths.directory.join("owner.json").exists());
    assert_eq!(
        fs::read_to_string(&f.paths.config).unwrap().trim_end(),
        f.original.trim_end()
    );
    titlebars::remove(&f.paths, &mut f.hypr).unwrap();
}
#[test]
fn existing_hyprbars_is_not_adopted() {
    let mut f = Fixture::new();
    f.hypr.loaded = true;
    assert!(f.setup().unwrap_err().contains("already in use"));
    assert!(!f.paths.directory.join("owner.json").exists());
    assert_eq!(fs::read_to_string(&f.paths.config).unwrap(), f.original);
}
#[test]
fn loaded_plugin_without_lua_support_is_unloaded_after_probe() {
    let mut f = Fixture::new();
    f.hypr.probe_ok = false;
    assert!(f.setup().unwrap_err().contains("Lua"));
    assert!(!f.hypr.loaded);
    assert_eq!(fs::read_to_string(&f.paths.config).unwrap(), f.original);
}
#[test]
fn setup_enable_preserves_unrelated_settings() {
    let mut f = Fixture::new();
    let p = f
        .paths
        .home
        .join(".config/omarchy/familiar-desktop-settings.json");
    common::atomic(&p, b"{\"widgetsEnabled\":false}").unwrap();
    f.args.enable = true;
    f.args.style = "windows".into();
    f.setup().unwrap();
    let v = common::read_json(&p).unwrap();
    assert_eq!(v["widgetsEnabled"], false);
    assert_eq!(v["titlebarMode"], "windows");
    assert_eq!(v["dockEnabled"], true);
}
#[test]
fn apply_updates_are_idempotent_and_disable_unloads() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    assert_eq!(f.apply().unwrap()["state"], "active");
    f.hypr.calls.clear();
    f.apply().unwrap();
    assert!(!f.hypr.calls.iter().any(|c| c == &["reload"]));
    f.args.background = "#123456".into();
    f.apply().unwrap();
    assert!(f.generated().contains("rgb(123456)"));
    f.args.operation = "disable".into();
    assert_eq!(f.apply().unwrap()["state"], "off");
    assert!(!f.hypr.loaded);
}
#[test]
fn stale_teardown_cannot_overwrite_new_instance() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    f.apply().unwrap();
    let text = f.generated();
    f.args.owner = "100-old".into();
    f.args.operation = "disable".into();
    f.args.if_owner = true;
    f.apply().unwrap();
    assert_eq!(f.generated(), text);
}
#[test]
fn stale_apply_cannot_overwrite_new_instance() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    f.apply().unwrap();
    let text = f.generated();
    f.args.owner = "100-old".into();
    f.args.style = "windows".into();
    f.apply().unwrap();
    assert_eq!(f.generated(), text);
}
#[test]
fn same_timestamp_different_instance_cannot_teardown_owner() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    f.apply().unwrap();
    let text = f.generated();
    f.args.owner = "200-other".into();
    f.args.operation = "disable".into();
    f.args.if_owner = true;
    f.apply().unwrap();
    assert_eq!(f.generated(), text);
}
#[test]
fn new_session_can_disable_previous_controls() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    f.apply().unwrap();
    f.args.owner = "300-restart".into();
    f.args.operation = "disable".into();
    assert_eq!(f.apply().unwrap()["state"], "off");
    assert!(!f.hypr.loaded);
}
#[test]
fn configuration_error_fails_closed() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    f.hypr.errors = "invalid window rule".into();
    assert!(f.apply().unwrap_err().contains("invalid window rule"));
    assert!(!f.generated().contains("hl.plugin.load"));
    assert!(!f.hypr.loaded);
}
#[test]
fn binary_mismatch_fails_closed() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    f.hypr.load_on_reload = false;
    assert!(f.apply().unwrap_err().contains("did not load"));
    assert!(!f.generated().contains("hl.plugin.load"));
}
#[test]
fn reload_failure_does_not_persist_active_config() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    f.hypr.fail_reload = true;
    assert!(f.apply().is_err());
    assert!(!f.generated().contains("hl.plugin.load"));
}
#[test]
fn damaged_or_reversed_markers_are_never_rewritten() {
    for tail in [
        format!("{BEGIN}\n"),
        format!("{}\n{BEGIN}\n", titlebars::END),
        format!("{BEGIN}\n{BEGIN}\n{}\n{}\n", titlebars::END, titlebars::END),
    ] {
        let mut f = Fixture::new();
        fs::write(&f.paths.config, &tail).unwrap();
        assert!(f.setup().is_err());
        assert_eq!(fs::read_to_string(&f.paths.config).unwrap(), tail);
    }
}
#[test]
fn ownership_collision_is_rejected() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    f.paths.source = PathBuf::from("/another/plugin");
    assert!(f.apply().unwrap_err().contains("another Familiar"));
    assert!(f.setup().unwrap_err().contains("another Familiar"));
}
#[test]
fn removed_hook_reports_setup_required() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    fs::write(&f.paths.config, &f.original).unwrap();
    assert_eq!(f.apply().unwrap()["state"], "setup-required");
}
#[test]
fn dependency_removed_after_start_reports_missing() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    fs::remove_file(f.args.library.as_ref().unwrap()).unwrap();
    assert_eq!(f.apply().unwrap()["state"], "missing");
}
#[test]
fn themes_change_enablement_and_every_visual_setting() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    f.args.mode = "theme".into();
    assert_eq!(f.apply().unwrap()["state"], "off");
    f.theme(json!({"schemaVersion":1,"titlebars":{"enabled":true,"style":"windows","height":40,"fontSize":16,"fontFamily":"Inter","background":"#fafafa","foreground":"#121212","closeColour":"#b42318","minimizeColour":"#62666c","maximizeColour":"#0067b8","buttonSize":20,"buttonPadding":12,"edgePadding":14,"textAlign":"left"}}));
    assert_eq!(f.apply().unwrap()["state"], "active");
    let text = f.generated();
    for fragment in [
        "bar_height = 40",
        "bar_text_size = 16",
        "bar_text_font = \"Inter\"",
        "bar_buttons_alignment = \"right\"",
        "rgb(fafafa)",
        "rgb(b42318)",
        "size = 20",
        "bar_button_padding = 12",
        "bar_padding = 14",
    ] {
        assert!(text.contains(fragment), "{fragment}");
    }
    f.theme(json!({"titlebars":{"enabled":false,"style":"mac"}}));
    assert_eq!(f.apply().unwrap()["state"], "off");
    assert!(!f.hypr.loaded);
}
#[test]
fn manual_style_overrides_theme_enablement_and_layout() {
    let args = Args {
        mode: "mac".into(),
        ..Args::default()
    };
    let p = titlebars::theme_policy(
        &json!({"titlebars":{"enabled":false,"style":"windows","height":42}}),
        &args,
    )
    .unwrap();
    assert_eq!(p["enabled"], true);
    assert_eq!(p["style"], "mac");
    assert_eq!(p["height"], 42);
    assert_eq!(p["minimizeColour"], "#ffbd44");
}
#[test]
fn shared_shell_font_and_palette_are_fallbacks() {
    let args = Args {
        font_family: "Theme Sans".into(),
        font_size: 15,
        background: "#eeeeee".into(),
        ..Args::default()
    };
    let p = titlebars::theme_policy(&json!({}), &args).unwrap();
    assert_eq!(p["fontFamily"], "Theme Sans");
    assert_eq!(p["fontSize"], 15);
    assert_eq!(p["background"], "#eeeeee");
}
#[test]
fn exclusions_merge_without_duplicates() {
    let args = Args {
        exclude: "kitty,firefox".into(),
        ..Args::default()
    };
    let p = titlebars::theme_policy(
        &json!({"titlebars":{"exclusions":["kitty","org.gnome.Nautilus"]}}),
        &args,
    )
    .unwrap();
    assert_eq!(
        p["exclusions"],
        json!(["kitty", "org.gnome.Nautilus", "firefox"])
    );
}
#[test]
fn invalid_theme_fails_closed_and_off_recovers() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    f.apply().unwrap();
    f.theme(json!({"titlebars":{"enabled":true,"height":5}}));
    assert!(f.apply().unwrap_err().contains("height"));
    assert!(!f.hypr.loaded);
    f.args.operation = "disable".into();
    assert_eq!(f.apply().unwrap()["state"], "off");
}
#[test]
fn invalid_and_unsafe_theme_values_are_rejected() {
    for v in [
        json!({"enabled":"true"}),
        json!({"style":"bad"}),
        json!({"height":true}),
        json!({"buttonSize":36,"height":24}),
        json!({"background":"red"}),
        json!({"fontFamily":"Sans\nwrong"}),
        json!({"exclusions":"kitty"}),
        json!({"buttonPadding":1000}),
        json!({"unknown":"value"}),
        json!({"fontSize":34}),
        json!({"textAlign":"right"}),
    ] {
        assert!(titlebars::theme_policy(&json!({"titlebars":v}), &Args::default()).is_err());
    }
    for version in [json!(true), json!(2), json!("1")] {
        assert!(
            titlebars::theme_policy(&json!({"schemaVersion":version}), &Args::default()).is_err()
        );
    }
}
#[test]
fn colours_cannot_inject_lua() {
    for colour in ["red", "#ffffff); os.execute('bad')", "#fff", "#12345z"] {
        assert!(titlebars::rgb(colour).is_err());
    }
}
#[test]
fn render_quotes_paths_classes_and_button_actions() {
    let f = Fixture::new();
    let p = titlebars::theme_policy(
        &json!({"titlebars":{"exclusions":["org.app+name","a\"; os.execute(\"bad\")"]}}),
        &f.args,
    )
    .unwrap();
    let text =
        titlebars::render(&f.paths, &PathBuf::from("a ' quoted path/hyprbars.so"), &p).unwrap();
    assert!(text.contains("org\\\\.app\\\\+name"));
    assert!(text.contains("a\\\";"));
    assert!(text.contains("familiar-desktop' titlebars action"));
    assert!(!text.contains("python"));
    // The pinned Hyprbars revision registers icon_on_hover, not buttons_on_hover.
    assert!(!text.contains("buttons_on_hover"));
    assert!(text.contains("icon_on_hover = "));
    assert!(text.contains("familiar-"));
}
#[test]
fn styles_change_order_and_alignment() {
    let f = Fixture::new();
    for style in ["mac", "windows"] {
        let args = Args {
            style: style.into(),
            ..Args::default()
        };
        let p = titlebars::theme_policy(&json!({}), &args).unwrap();
        let text = titlebars::render(&f.paths, f.args.library.as_ref().unwrap(), &p).unwrap();
        assert!(text.contains(if style == "mac" {
            "bar_buttons_alignment = \"left\""
        } else {
            "bar_buttons_alignment = \"right\""
        }));
        assert!(text.contains(&format!("familiar-{style}-close")));
        assert!(text.contains(&format!("familiar-{style}-minimize")));
        assert!(text.contains(&format!("familiar-{style}-maximize")));
        assert!(text.contains(&format!("icon_on_hover = {}", style == "mac")));
        let buttons = &text[text.find("add_button").unwrap()..];
        let min = buttons.find("action minimize").unwrap();
        let max = buttons.find("action maximize").unwrap();
        assert_eq!(min < max, style == "mac");
        assert!(text.contains("familiar-titlebars-browsers"));
        let included = titlebars::theme_policy(
            &json!({}),
            &Args {
                include_browsers: true,
                ..args.clone()
            },
        )
        .unwrap();
        assert!(
            !titlebars::render(&f.paths, f.args.library.as_ref().unwrap(), &included)
                .unwrap()
                .contains("familiar-titlebars-browsers")
        );
    }
}
struct ActiveFake {
    value: String,
    calls: Vec<Vec<String>>,
}
impl Hypr for ActiveFake {
    fn command(&mut self, args: &[&str]) -> Result<String> {
        self.calls
            .push(args.iter().map(|s| s.to_string()).collect());
        if args == ["-j", "activewindow"] {
            Ok(self.value.clone())
        } else {
            Ok("ok".into())
        }
    }
}
#[test]
fn close_and_maximize_dispatch_explicit_addresses() {
    for action in ["close", "maximize"] {
        let mut h = ActiveFake {
            value: "{\"address\":\"0xABC\"}".into(),
            calls: vec![],
        };
        titlebars::window_action(action, &mut h).unwrap();
        assert!(h.calls.last().unwrap()[1].contains("address:0xABC"));
    }
}
#[test]
fn invalid_active_address_never_dispatches() {
    for value in ["{\"address\":\"0xA; bad\"}", "[]", "bad JSON"] {
        let mut h = ActiveFake {
            value: value.into(),
            calls: vec![],
        };
        assert!(titlebars::window_action("minimize", &mut h).is_err());
        assert_eq!(h.calls.len(), 1);
    }
}
#[test]
fn option_parser_preserves_literal_font_and_class_values() {
    let a = Args::parse(
        &[
            "apply",
            "--mode",
            "theme",
            "--font-family",
            "Inter '$HOME'",
            "--exclude",
            "a;bad",
        ]
        .map(str::to_string),
    )
    .unwrap();
    assert_eq!(a.font_family, "Inter '$HOME'");
    assert_eq!(a.exclude, "a;bad");
    for values in [
        vec!["apply", "--bad"],
        vec!["apply", "--mode"],
        vec!["action", "unknown", "--style", "bad"],
    ] {
        assert!(Args::parse(&values.iter().map(|s| s.to_string()).collect::<Vec<_>>()).is_err());
    }
}

#[test]
fn larger_controls_override_geometry_without_enabling_disabled_bars() {
    let mut args = familiar_desktop::titlebars::Args {
        mode: "theme".into(),
        size: "large".into(),
        ..Default::default()
    };
    let p = familiar_desktop::titlebars::theme_policy(&serde_json::json!({}), &args).unwrap();
    assert_eq!(p["enabled"], false);
    assert_eq!(p["height"], 44);
    assert_eq!(p["buttonSize"], 26);
    args.size = "extra-large".into();
    assert_eq!(
        familiar_desktop::titlebars::theme_policy(&serde_json::json!({}), &args).unwrap()["height"],
        52
    );
    args.size = "huge".into();
    assert!(familiar_desktop::titlebars::theme_policy(&serde_json::json!({}), &args).is_err());
}

#[test]
fn remove_preserves_exact_bytes_permissions_and_later_edits() {
    use std::os::unix::fs::PermissionsExt;
    for original in ["-- no newline", "-- spaces  \n\n\n", ""] {
        let mut f = Fixture::new();
        fs::write(&f.paths.config, original).unwrap();
        fs::set_permissions(&f.paths.config, fs::Permissions::from_mode(0o640)).unwrap();
        f.setup().unwrap();
        f.setup().unwrap();
        let text = fs::read_to_string(&f.paths.config).unwrap() + "\n-- subsequent user edit\n";
        fs::write(&f.paths.config, text).unwrap();
        titlebars::remove(&f.paths, &mut f.hypr).unwrap();
        assert_eq!(
            fs::read_to_string(&f.paths.config).unwrap(),
            format!("{original}\n-- subsequent user edit\n")
        );
        assert_eq!(
            fs::metadata(&f.paths.config).unwrap().permissions().mode() & 0o777,
            0o640
        );
    }
}

#[test]
fn edited_foreign_or_unowned_hooks_block_removal_without_data_loss() {
    for variant in ["edit", "foreign", "missing-owner"] {
        let mut f = Fixture::new();
        f.setup().unwrap();
        if variant == "edit" {
            let text = fs::read_to_string(&f.paths.config)
                .unwrap()
                .replace("dofile", "print");
            fs::write(&f.paths.config, text).unwrap();
        } else if variant == "foreign" {
            f.paths.source = PathBuf::from("/foreign/plugin");
        } else {
            fs::remove_file(f.paths.directory.join("owner.json")).unwrap();
        }
        let before = fs::read(&f.paths.config).unwrap();
        assert!(titlebars::remove(&f.paths, &mut f.hypr).is_err());
        assert_eq!(fs::read(&f.paths.config).unwrap(), before);
        assert!(f.paths.directory.join("titlebars.lua").exists());
    }
}

#[test]
fn symlink_config_is_never_replaced() {
    use std::os::unix::fs::symlink;
    let mut f = Fixture::new();
    let target = f.paths.config.with_extension("personal");
    fs::rename(&f.paths.config, &target).unwrap();
    symlink(&target, &f.paths.config).unwrap();
    assert!(f.setup().is_err());
    assert!(
        fs::symlink_metadata(&f.paths.config)
            .unwrap()
            .file_type()
            .is_symlink()
    );
    assert_eq!(fs::read_to_string(target).unwrap(), f.original);
}

#[test]
fn failed_remove_retains_hook_and_ownership_for_retry() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    f.apply().unwrap();
    let before = fs::read(&f.paths.config).unwrap();
    f.hypr.fail_reload = true;
    assert!(titlebars::remove(&f.paths, &mut f.hypr).is_err());
    assert_eq!(fs::read(&f.paths.config).unwrap(), before);
    assert!(f.paths.directory.join("owner.json").exists());
    assert!(f.paths.directory.join("titlebars.lua").exists());
    f.hypr.fail_reload = false;
    titlebars::remove(&f.paths, &mut f.hypr).unwrap();
    assert!(!f.hypr.loaded);
}

#[test]
fn legacy_hook_migrates_surgically_without_restoring_unknown_old_whitespace() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    let owner_path = f.paths.directory.join("owner.json");
    let mut state = common::read_json(&owner_path).unwrap();
    state.as_object_mut().unwrap().remove("hookVersion");
    common::atomic(&owner_path, state.to_string().as_bytes()).unwrap();
    // Legacy install trimmed before adding two newlines. Its pre-install bytes
    // cannot be reconstructed; migration preserves the current personal prefix.
    let installed = fs::read_to_string(&f.paths.config).unwrap();
    let baseline = installed.split(BEGIN).next().unwrap().to_owned();
    f.setup().unwrap();
    titlebars::remove(&f.paths, &mut f.hypr).unwrap();
    assert_eq!(fs::read_to_string(&f.paths.config).unwrap(), baseline);
}

#[test]
fn existing_owner_does_not_authorize_adopting_a_loaded_backend() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    f.hypr.loaded = true;
    f.hypr.calls.clear();
    let before = f.generated();
    assert!(f.setup().unwrap_err().contains("already in use"));
    assert_eq!(f.generated(), before);
    assert_eq!(f.hypr.calls, vec![vec!["-j", "plugin", "list"]]);
}

#[test]
fn system_and_symlinked_libraries_are_never_owned_or_unloaded() {
    use std::os::unix::fs::symlink;
    for indirect in [false, true] {
        let mut f = Fixture::new();
        f.setup().unwrap();
        let foreign = f.paths.home.join("foreign/hyprbars.so");
        fs::create_dir_all(foreign.parent().unwrap()).unwrap();
        fs::write(&foreign, "shared backend").unwrap();
        let candidate = if indirect {
            let p = f.paths.source.join("bin/hyprbars/alias/hyprbars.so");
            fs::create_dir_all(p.parent().unwrap()).unwrap();
            symlink(&foreign, &p).unwrap();
            p
        } else {
            foreign.clone()
        };
        f.args.library = Some(candidate.clone());
        f.hypr.calls.clear();
        assert!(f.setup().unwrap_err().contains("outside Familiar"));
        let state_file = f.paths.directory.join("owner.json");
        let mut state = common::read_json(&state_file).unwrap();
        state["library"] = json!(candidate);
        common::atomic(&state_file, state.to_string().as_bytes()).unwrap();
        let before = fs::read_to_string(&f.paths.config).unwrap();
        assert!(f.apply().unwrap_err().contains("outside Familiar"));
        assert!(
            titlebars::remove(&f.paths, &mut f.hypr)
                .unwrap_err()
                .contains("outside Familiar")
        );
        assert_eq!(fs::read_to_string(&f.paths.config).unwrap(), before);
        assert!(
            !f.hypr
                .calls
                .iter()
                .any(|c| c[0] == "plugin" || c[0] == "reload")
        );
        assert_eq!(fs::read_to_string(foreign).unwrap(), "shared backend");
    }
}

#[test]
fn official_package_pauses_loader_without_touching_shared_backend_or_settings() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    f.apply().unwrap();
    assert!(f.generated().contains("local official = io.open"));
    fs::create_dir_all(f.paths.official_library.parent().unwrap()).unwrap();
    fs::write(&f.paths.official_library, "official").unwrap();
    f.hypr.calls.clear();
    assert!(
        f.setup()
            .unwrap_err()
            .contains("Omarchy's titlebar package")
    );
    assert_eq!(f.apply().unwrap()["state"], "migration-required");
    assert!(!f.generated().contains("hl.plugin.load"));
    f.args.operation = "disable".into();
    assert_eq!(f.apply().unwrap()["state"], "migration-required");
    titlebars::remove(&f.paths, &mut f.hypr).unwrap();
    assert!(f.hypr.calls.is_empty());
    assert_eq!(fs::read_to_string(&f.paths.config).unwrap(), f.original);
    assert_eq!(
        fs::read_to_string(&f.paths.official_library).unwrap(),
        "official"
    );
}

#[test]
fn fresh_official_host_does_not_offer_competing_setup() {
    let mut f = Fixture::new();
    fs::create_dir_all(f.paths.official_library.parent().unwrap()).unwrap();
    fs::write(&f.paths.official_library, "official v0.2.0").unwrap();
    let original = fs::read_to_string(&f.paths.config).unwrap();
    assert_eq!(f.apply().unwrap()["state"], "migration-required");
    assert!(f.setup().is_err());
    assert!(f.hypr.calls.is_empty());
    assert!(!f.paths.directory.join("owner.json").exists());
    assert_eq!(fs::read_to_string(&f.paths.config).unwrap(), original);
}

fn official(f: &Fixture) {
    fs::create_dir_all(f.paths.official_library.parent().unwrap()).unwrap();
    fs::write(&f.paths.official_library, "official").unwrap();
}

#[test]
fn official_migration_keeps_preferences_and_reconciles_after_restart() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    f.apply().unwrap();
    let config = fs::read(&f.paths.config).unwrap();
    let prefs = f
        .paths
        .home
        .join(".config/omarchy/familiar-desktop-settings.json");
    common::atomic(&prefs, br#"{"titlebarMode":"mac","dockEnabled":false}"#).unwrap();
    official(&f);
    f.hypr.calls.clear();
    assert_eq!(
        titlebars::migrate(&f.paths, &mut f.hypr).unwrap()["state"],
        "restart-required"
    );
    assert!(f.hypr.calls.is_empty());
    assert_eq!(fs::read(&f.paths.config).unwrap(), config);
    assert!(!f.generated().contains("hl.plugin.load"));
    assert_eq!(common::read_json(&prefs).unwrap()["titlebarMode"], "mac");
    assert_eq!(common::read_json(&prefs).unwrap()["dockEnabled"], false);
    assert_eq!(f.apply().unwrap()["state"], "restart-required");
    f.paths.compositor_session = "session-after".into();
    assert_eq!(f.apply().unwrap()["state"], "configured");
    assert!(f.generated().contains("familiar_configure"));
    assert!(!f.generated().contains("hl.plugin.load("));
    f.args.operation = "disable".into();
    assert_eq!(f.apply().unwrap()["state"], "managed");
    assert!(f.hypr.calls.iter().all(|c| c[0] != "plugin"));
    assert!(f.setup().unwrap_err().contains("will not recreate"));
    titlebars::remove(&f.paths, &mut f.hypr).unwrap();
    assert_eq!(fs::read_to_string(&f.paths.config).unwrap(), f.original);
    assert_eq!(
        fs::read_to_string(&f.paths.official_library).unwrap(),
        "official"
    );
}

#[test]
fn fresh_official_handoff_needs_core_but_does_not_require_private_assets() {
    let mut f = Fixture::new();
    official(&f);
    fs::remove_dir_all(f.paths.source.join("bin")).unwrap();
    f.hypr.probe_ok = false;
    assert_eq!(
        titlebars::migrate(&f.paths, &mut f.hypr).unwrap()["state"],
        "core-required"
    );
    f.hypr.probe_ok = true;
    assert_eq!(f.apply().unwrap()["state"], "configured");
    assert_eq!(
        titlebars::strip_hook(&fs::read_to_string(&f.paths.config).unwrap())
            .unwrap()
            .trim_end(),
        f.original.trim_end()
    );
    // Core may have no floating workspace, hence no loaded titlebars. This is
    // delegation, not a claim that a backend is loaded or controls are visible.
    assert!(!f.hypr.loaded);
}

#[test]
fn removed_package_never_resurrects_the_private_backend() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    official(&f);
    titlebars::migrate(&f.paths, &mut f.hypr).unwrap();
    fs::remove_file(&f.paths.official_library).unwrap();
    assert_eq!(f.apply().unwrap()["state"], "package-missing");
    assert!(f.setup().is_err());
    assert!(!f.generated().contains("hl.plugin.load"));
    assert!(f.hypr.calls.iter().all(|c| c.first().unwrap() != "reload"));
}

#[test]
fn interrupted_handoff_is_retryable_and_never_restores_the_fork() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    official(&f);
    let generated = f.paths.directory.join("titlebars.lua");
    fs::remove_file(&generated).unwrap();
    fs::create_dir(&generated).unwrap(); // Force the loader write to fail.
    assert!(titlebars::migrate(&f.paths, &mut f.hypr).is_err());
    assert_eq!(f.apply().unwrap()["state"], "migration-required");
    fs::remove_dir(&generated).unwrap();
    assert_eq!(
        titlebars::migrate(&f.paths, &mut f.hypr).unwrap()["state"],
        "restart-required"
    );
    assert!(!f.generated().contains("hl.plugin.load"));
    f.paths.compositor_session = "session-after".into();
    assert_eq!(
        titlebars::migrate(&f.paths, &mut f.hypr).unwrap()["state"],
        "ready"
    );
}

#[test]
fn migration_rejects_edited_hook_foreign_owner_and_unknown_session() {
    let mut f = Fixture::new();
    f.setup().unwrap();
    official(&f);
    let before = fs::read(f.paths.directory.join("owner.json")).unwrap();
    let config = fs::read_to_string(&f.paths.config).unwrap();
    fs::write(
        &f.paths.config,
        config.replace("familiarFile:close()", "-- personal edit"),
    )
    .unwrap();
    assert!(titlebars::migrate(&f.paths, &mut f.hypr).is_err());
    fs::write(&f.paths.config, config).unwrap();
    f.paths.compositor_session.clear();
    assert!(titlebars::migrate(&f.paths, &mut f.hypr).is_err());
    f.paths.compositor_session = "known".into();
    f.paths.source = f.paths.home.join("other-install");
    assert!(titlebars::migrate(&f.paths, &mut f.hypr).is_err());
    assert_eq!(
        fs::read(f.paths.directory.join("owner.json")).unwrap(),
        before
    );
}

#[test]
fn official_controls_execute_against_real_core_configuration() {
    let f = Fixture::new();
    official(&f);
    let source = f.paths.source.join("backend/src/titlebars.rs");
    fs::create_dir_all(source.parent().unwrap()).unwrap();
    fs::write(&source, "// Familiar official-titlebar controls v2").unwrap();
    let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../tests/fixtures/titlebars");
    for style in ["mac", "windows"] {
        let args = Args {
            style: style.into(),
            size: "large".into(),
            font_family: "Test Font".into(),
            background: "#abcdef".into(),
            foreground: "#121212".into(),
            exclude: "org.app+name".into(),
            ..Args::default()
        };
        let policy = titlebars::theme_policy(&json!({}), &args).unwrap();
        let generated = f.paths.directory.join("official.lua");
        fs::write(
            &generated,
            titlebars::render_official(&f.paths, &policy).unwrap(),
        )
        .unwrap();
        for scenario in [
            "floating",
            "tiled",
            "first-load",
            "changed-core",
            "core-error",
            "late",
            "conflict",
            "old-source",
        ] {
            fs::write(
                &source,
                if scenario == "old-source" {
                    "// old source"
                } else {
                    "// Familiar official-titlebar controls v2"
                },
            )
            .unwrap();
            let output = std::process::Command::new("lua")
                .arg(fixtures.join("exercise.lua"))
                .arg(&generated)
                .arg(fixtures.join("workspace-modes.lua"))
                .args([style, scenario])
                .output()
                .expect("Lua is required to test the Core adapter");
            assert!(
                output.status.success(),
                "{style}/{scenario}: {}",
                String::from_utf8_lossy(&output.stderr)
            );
        }
    }
}

#[test]
fn official_reconcile_is_idempotent_and_stale_teardown_cannot_reset_controls() {
    let mut f = Fixture::new();
    official(&f);
    titlebars::migrate(&f.paths, &mut f.hypr).unwrap();
    f.apply().unwrap();
    let generated = f.generated();
    f.hypr.calls.clear();
    f.apply().unwrap();
    assert!(!f.hypr.calls.iter().any(|c| c[0] == "reload"));
    f.args.operation = "disable".into();
    f.args.if_owner = true;
    f.args.owner = "100-old".into();
    f.apply().unwrap();
    assert_eq!(f.generated(), generated);
    f.args.owner = "200-new".into();
    f.apply().unwrap();
    assert!(!f.generated().contains("familiar_configure"));
    assert!(f.hypr.calls.iter().all(|c| c[0] != "plugin"));
}

#[test]
fn official_failed_reload_restores_previous_generated_controls() {
    let mut f = Fixture::new();
    official(&f);
    titlebars::migrate(&f.paths, &mut f.hypr).unwrap();
    f.apply().unwrap();
    let original = f.generated();
    f.args.style = "windows".into();
    f.hypr.fail_reload = true;
    assert!(f.apply().is_err());
    assert_eq!(f.generated(), original);
}

#[test]
fn clicked_target_never_falls_back_to_the_newly_focused_window() {
    let mut f = Fixture::new();
    for action in ["close", "maximize"] {
        f.hypr.calls.clear();
        titlebars::window_action_at(action, "0xabc123", &mut f.hypr).unwrap();
        assert_eq!(f.hypr.calls.len(), 1);
        assert_eq!(f.hypr.calls[0][0], "dispatch");
        assert!(f.hypr.calls[0][1].contains("address:0xabc123"));
    }
    for target in ["%WINDOW%", "0x1'; rm -rf x", "focused", "address:0x123"] {
        f.hypr.calls.clear();
        assert!(titlebars::window_action_at("minimize", target, &mut f.hypr).is_err());
        assert!(f.hypr.calls.is_empty());
    }
    let args = Args::parse(&[
        "action".into(),
        "minimize".into(),
        "--window".into(),
        "0x123".into(),
    ])
    .unwrap();
    assert_eq!(args.window, "0x123");
}
