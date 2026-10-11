use crate::{
    Result,
    common::{self, Hypr, atomic, checked, lua, read_json, shell_quote},
};
use serde_json::{Value, json};
use std::{
    env, fs,
    path::{Path, PathBuf},
};

pub const BEGIN: &str = "-- BEGIN Familiar Desktop title bars";
pub const END: &str = "-- END Familiar Desktop title bars";
pub const OFFICIAL_LIBRARY: &str = "/usr/lib/omarchy-hyprland-titlebars/titlebars.so";
// Familiar official-titlebar handoff v1
// Familiar official-titlebar controls v2
const MIGRATION_REQUIRED: &str = "Omarchy's titlebar package is installed. Choose Use Familiar controls to retire the private loader and apply your saved style with Omarchy’s renderer.";
#[derive(Clone, Debug)]
pub struct Args {
    pub operation: String,
    pub action: String,
    pub owner: String,
    pub window: String,
    pub if_owner: bool,
    pub style: String,
    pub mode: String,
    pub background: String,
    pub foreground: String,
    pub font_family: String,
    pub font_size: i64,
    pub size: String,
    pub exclude: String,
    pub include_browsers: bool,
    pub library: Option<PathBuf>,
    pub install_dependency: bool,
    pub enable: bool,
}
impl Default for Args {
    fn default() -> Self {
        Self {
            operation: "apply".into(),
            action: String::new(),
            owner: String::new(),
            window: String::new(),
            if_owner: false,
            style: "mac".into(),
            mode: String::new(),
            background: "#202020".into(),
            foreground: "#ffffff".into(),
            font_family: "Sans".into(),
            font_size: 13,
            size: "default".into(),
            exclude: String::new(),
            include_browsers: false,
            library: None,
            install_dependency: false,
            enable: false,
        }
    }
}
impl Args {
    pub fn parse(argv: &[String]) -> Result<Self> {
        let mut a = Self {
            operation: argv.first().ok_or("Choose a title-bar operation")?.clone(),
            ..Self::default()
        };
        if !["setup", "apply", "disable", "remove", "action", "migrate"]
            .contains(&a.operation.as_str())
        {
            return Err("Unknown title-bar operation".into());
        }
        let mut i = 1;
        if a.operation == "action" {
            a.action = argv.get(i).ok_or("Choose a window action")?.clone();
            i += 1;
        }
        while i < argv.len() {
            let key = &argv[i];
            i += 1;
            match key.as_str() {
                "--if-owner" => a.if_owner = true,
                "--enable" => a.enable = true,
                "--include-browsers" => a.include_browsers = true,
                "--install-dependency" => a.install_dependency = true,
                "--window" | "--owner" | "--style" | "--mode" | "--background" | "--foreground"
                | "--size" | "--font-family" | "--font-size" | "--exclude" | "--library" => {
                    let value = argv
                        .get(i)
                        .ok_or_else(|| format!("Missing value for {key}"))?
                        .clone();
                    i += 1;
                    match key.as_str() {
                        "--window" => {
                            if !crate::dock::valid_address(&value) {
                                return Err("Invalid window address".into());
                            }
                            a.window = value;
                        }
                        "--owner" => a.owner = value,
                        "--style" => a.style = value,
                        "--mode" => a.mode = value,
                        "--background" => a.background = value,
                        "--foreground" => a.foreground = value,
                        "--font-family" => a.font_family = value,
                        "--size" => a.size = value,
                        "--font-size" => {
                            a.font_size = value.parse().map_err(|_| "Invalid font size")?
                        }
                        "--exclude" => a.exclude = value,
                        "--library" => a.library = Some(PathBuf::from(value)),
                        _ => unreachable!(),
                    }
                }
                _ => return Err(format!("Unknown title-bar option {key}")),
            }
        }
        if !["mac", "windows"].contains(&a.style.as_str())
            || !["", "theme", "off", "mac", "windows"].contains(&a.mode.as_str())
        {
            return Err("Unknown window-control style/mode".into());
        }
        Ok(a)
    }
}
#[derive(Clone)]
pub struct Paths {
    pub home: PathBuf,
    pub source: PathBuf,
    pub binary: PathBuf,
    pub directory: PathBuf,
    pub config: PathBuf,
    pub official_library: PathBuf,
    pub compositor_session: String,
}
impl Paths {
    pub fn system() -> Result<Self> {
        let home = common::home()?;
        let binary = env::current_exe().map_err(|e| e.to_string())?;
        let source = binary
            .parent()
            .and_then(Path::parent)
            .ok_or("Install the helper in the plugin bin directory")?
            .to_path_buf();
        let config = common::config_home()?;
        Ok(Self {
            home,
            source,
            binary,
            directory: config.join("omarchy/familiar-titlebars"),
            config: config.join("hypr/looknfeel.lua"),
            official_library: PathBuf::from(OFFICIAL_LIBRARY),
            compositor_session: env::var("HYPRLAND_INSTANCE_SIGNATURE").unwrap_or_default(),
        })
    }
}
pub fn rgb(value: &str) -> Result<String> {
    if value.len() != 7
        || !value.starts_with('#')
        || !value[1..].bytes().all(|b| b.is_ascii_hexdigit())
    {
        return Err("Expected a six-digit theme colour".into());
    }
    Ok(format!("rgb({})", &value[1..]))
}
fn plain(s: &str) -> bool {
    !s.is_empty() && s.chars().count() <= 200 && !s.chars().any(char::is_control)
}
pub fn theme_policy(document: &Value, args: &Args) -> Result<Value> {
    if document.get("schemaVersion").unwrap_or(&json!(1)).as_u64() != Some(1) {
        return Err("Unsupported familiar-desktop.json schemaVersion".into());
    }
    let theme = document.get("titlebars").cloned().unwrap_or(json!({}));
    let theme = theme
        .as_object()
        .ok_or("Theme titlebars must be an object")?;
    let mut options = json!({"enabled":false,"style":"windows","height":34,"fontSize":args.font_size,"fontFamily":args.font_family,"textAlign":"center","buttonSize":18,"edgePadding":10,"buttonPadding":9,"background":args.background,"foreground":args.foreground,"buttonForeground":null,"closeColour":"#ff605c","minimizeColour":null,"maximizeColour":null,"exclusions":[]});
    for (key, value) in theme {
        if options.get(key).is_none() {
            return Err(format!("Unknown title-bar theme key: {key}"));
        }
        options[key] = value.clone();
    }
    if options["enabled"].as_bool().is_none()
        || !matches!(options["style"].as_str(), Some("mac" | "windows"))
    {
        return Err("Theme requires boolean enabled and mac/windows style".into());
    }
    let mode = if args.mode.is_empty() {
        &args.style
    } else {
        &args.mode
    };
    match mode.as_str() {
        "mac" | "windows" => {
            options["enabled"] = json!(true);
            options["style"] = json!(mode);
        }
        "off" => options["enabled"] = json!(false),
        "theme" => {}
        _ => return Err("Unknown window-control mode".into()),
    }
    match args.size.as_str() {
        "default" => {}
        "large" => {
            options["height"] = json!(44);
            options["buttonSize"] = json!(26);
            options["fontSize"] = json!(15);
        }
        "extra-large" => {
            options["height"] = json!(52);
            options["buttonSize"] = json!(32);
            options["fontSize"] = json!(17);
        }
        _ => return Err("Unknown title-bar size".into()),
    }
    for (key, min, max) in [
        ("height", 24, 80),
        ("fontSize", 8, 32),
        ("buttonSize", 12, 36),
        ("edgePadding", 0, 40),
        ("buttonPadding", 2, 30),
    ] {
        let n = options[key]
            .as_i64()
            .ok_or_else(|| format!("Theme {key} must be an integer"))?;
        if n < min || n > max {
            return Err(format!("Theme {key} is outside its supported range"));
        }
    }
    if options["buttonSize"].as_i64().unwrap() > options["height"].as_i64().unwrap() - 4
        || options["fontSize"].as_i64().unwrap() > options["height"].as_i64().unwrap() - 4
    {
        return Err("Theme height must leave room for its buttons and text".into());
    }
    if !matches!(options["textAlign"].as_str(), Some("left" | "center")) {
        return Err("Theme textAlign must be left or center".into());
    }
    if !options["fontFamily"].as_str().is_some_and(plain) {
        return Err("Theme fontFamily must be a plain font name".into());
    }
    let mac = options["style"] == "mac";
    if options["buttonForeground"].is_null() {
        options["buttonForeground"] = if mac {
            json!("#302820")
        } else {
            json!("#ffffff")
        };
    }
    for (key, fallback) in [
        ("minimizeColour", if mac { "#ffbd44" } else { "#646d7e" }),
        ("maximizeColour", if mac { "#00ca4e" } else { "#646d7e" }),
    ] {
        if options[key].is_null() {
            options[key] = json!(fallback);
        }
    }
    for key in [
        "background",
        "foreground",
        "buttonForeground",
        "closeColour",
        "minimizeColour",
        "maximizeColour",
    ] {
        rgb(options[key]
            .as_str()
            .ok_or("Expected theme colour string")?)?;
    }
    let mut exclusions = Vec::<String>::new();
    for value in options["exclusions"]
        .as_array()
        .ok_or("Theme exclusions must be a list of window classes")?
    {
        let s = value.as_str().ok_or("Exclusions must be strings")?;
        if !plain(s) {
            return Err("Invalid excluded window class".into());
        }
        if !exclusions.iter().any(|x| x == s) {
            exclusions.push(s.into());
        }
    }
    for s in args
        .exclude
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        if !plain(s) {
            return Err("Invalid excluded window class".into());
        }
        if !exclusions.iter().any(|x| x == s) {
            exclusions.push(s.into());
        }
    }
    if exclusions.len() > 32 {
        return Err("Use up to 32 excluded window classes".into());
    }
    options["exclusions"] = json!(exclusions);
    options["skipBrowserTitlebars"] = json!(!args.include_browsers);
    Ok(options)
}
pub fn render(paths: &Paths, library: &Path, o: &Value) -> Result<String> {
    let mut s = format!(
        "-- Generated by Familiar Desktop; configure it from Familiar's settings.\nlocal manifest = io.open({}, 'r')\nif not manifest then return end\nmanifest:close()\nlocal library = io.open({}, 'r')\nif not library then return end\nlibrary:close()\nhl.plugin.load({})\nif not hl.plugin.hyprbars then return end\nhl.config({{ plugin = {{ hyprbars = {{\n",
        lua(&paths.source.join("manifest.json").to_string_lossy()),
        lua(&library.to_string_lossy()),
        lua(&library.to_string_lossy())
    );
    // Rechecked by the compositor on every config reload, including reloads
    // before the Familiar service has had a chance to reconcile.
    s = format!(
        "-- Prefer Omarchy's system titlebar backend; never load both.\nlocal official = io.open({}, 'r')\nif official then official:close(); return end\n{}",
        lua(&paths.official_library.to_string_lossy()),
        s
    );
    s += &render_controls(paths, o, false)?;
    Ok(s)
}

fn render_controls(paths: &Paths, o: &Value, official: bool) -> Result<String> {
    let action = |name: &str| {
        shell_quote(&paths.binary.to_string_lossy())
            + " titlebars action "
            + name
            + if official { " --window '%WINDOW%'" } else { "" }
    };
    let mut s = format!(
        "  enabled = true, bar_height = {}, bar_text_size = {},\n  bar_title_enabled = true, bar_text_font = {}, bar_text_align = {},\n  bar_color = {}, ['col.text'] = {},\n  bar_buttons_alignment = {},\n  bar_padding = {}, bar_button_padding = {}, bar_part_of_window = true,\n  icon_on_hover = {},\n  on_double_click = {},\n}} }} }})\n",
        o["height"],
        o["fontSize"],
        lua(o["fontFamily"].as_str().ok_or("Missing font")?),
        lua(o["textAlign"].as_str().ok_or("Missing alignment")?),
        lua(&rgb(o["background"]
            .as_str()
            .ok_or("Missing background")?)?),
        lua(&rgb(o["foreground"]
            .as_str()
            .ok_or("Missing foreground")?)?),
        lua(if o["style"] == "mac" { "left" } else { "right" }),
        o["edgePadding"],
        o["buttonPadding"],
        o["style"] == "mac",
        lua(&action("maximize"))
    );
    if official {
        s += &format!(
            "hl.config({{ plugin = {{ hyprbars = {{ button_rounding = {}, inactive_button_color = 'rgba(00000000)', bar_color_inactive = 'rgba(00000000)' }} }} }})\n",
            if o["style"] == "mac" { -1 } else { 3 }
        );
    }
    let mut buttons = vec![
        ("close", "closeColour"),
        ("minimize", "minimizeColour"),
        ("maximize", "maximizeColour"),
    ];
    if o["style"] == "windows" {
        buttons.swap(1, 2);
    }
    for (name, key) in buttons {
        s += &format!(
            "hl.plugin.hyprbars.add_button({{ bg_color = {}, fg_color = {}, size = {}, icon = {}, action = {} }})\n",
            lua(&rgb(o[key].as_str().ok_or("Missing button colour")?)?),
            lua(&rgb(o["buttonForeground"]
                .as_str()
                .ok_or("Missing foreground")?)?),
            o["buttonSize"],
            lua(&if official {
                match name {
                    "close" => "×",
                    "minimize" => "−",
                    _ if o["style"] == "mac" => "+",
                    _ => "□",
                }
                .into()
            } else {
                format!(
                    "familiar-{}-{name}",
                    o["style"].as_str().ok_or("Missing style")?
                )
            }),
            lua(&action(name))
        );
    }
    if o["skipBrowserTitlebars"] != false {
        // Chrome/Chromium already put window controls in their tab strip.
        // Match actual browser classes, leaving separately named web apps alone.
        s += "hl.window_rule({ name = 'familiar-titlebars-browsers', match = { class = '(?i)^(google-chrome(-beta|-unstable)?|chromium(-browser)?)$' }, ['hyprbars:no_bar'] = true })\n";
    }
    for (i, cls) in o["exclusions"]
        .as_array()
        .ok_or("Missing exclusions")?
        .iter()
        .enumerate()
    {
        s += &format!(
            "hl.window_rule({{ name = 'familiar-titlebars-exclude-{i}', match = {{ class = {} }}, ['hyprbars:no_bar'] = true }})\n",
            lua(&format!(
                "^({})$",
                regex::escape(cls.as_str().ok_or("Invalid class")?)
            ))
        );
    }
    Ok(s)
}
/// Configure the stock renderer inside Core's single workspace-mode apply pass.
/// The adapter does not patch installed Core files or load a compositor plugin.
pub fn render_official(paths: &Paths, options: &Value) -> Result<String> {
    let mut text = format!(
        "-- Familiar official renderer configuration.\nlocal manifest = io.open({}, 'r')\nif not manifest then return end\nmanifest:close()\nlocal official = io.open({}, 'r')\nif not official then return end\nofficial:close()\nlocal source = io.open({}, 'r')\nif not source then return end\nlocal compatible = source:read('*a'):find('Familiar official-titlebar controls v2', 1, true)\nsource:close()\nif not compatible then return end\nlocal function familiar_configure()\nhl.config({{ plugin = {{ hyprbars = {{\n",
        lua(&paths.source.join("manifest.json").to_string_lossy()),
        lua(&paths.official_library.to_string_lossy()),
        lua(&paths
            .source
            .join("backend/src/titlebars.rs")
            .to_string_lossy()),
    );
    text += &render_controls(paths, options, true)?;
    text += "end\n";
    text += include_str!("official_titlebars.lua");
    Ok(text)
}

pub fn strip_hook(text: &str) -> Result<String> {
    if text.matches(BEGIN).count() != text.matches(END).count() || text.matches(BEGIN).count() > 1 {
        return Err("Familiar's configuration markers are damaged; no file was changed".into());
    }
    if let Some(start) = text.find(BEGIN) {
        let end = text.find(END).ok_or("Damaged markers")? + END.len();
        if end < start {
            return Err("Damaged markers".into());
        }
        let end = if text[end..].starts_with('\n') {
            end + 1
        } else {
            end
        };
        Ok(format!("{}{}", &text[..start], &text[end..]))
    } else {
        Ok(text.into())
    }
}
fn include_hook(paths: &Paths) -> String {
    let generated = paths.directory.join("titlebars.lua");
    format!(
        "{BEGIN}\nlocal familiarFile = io.open({}, 'r')\nif familiarFile then\n  familiarFile:close()\n  dofile({})\nend\n{END}\n",
        lua(&generated.to_string_lossy()),
        lua(&generated.to_string_lossy())
    )
}
fn owned_config(paths: &Paths, state: &Value, text: &str) -> Result<String> {
    let has_owner = state.as_object().is_some_and(|o| !o.is_empty());
    if has_owner
        && (state["source"].as_str() != Some(paths.source.to_string_lossy().as_ref())
            || state["config"].as_str() != Some(paths.config.to_string_lossy().as_ref()))
    {
        return Err("Title bars belong to another Familiar installation; no file changed".into());
    }
    if !has_owner && (text.contains(BEGIN) || text.contains(END)) {
        return Err("Title-bar hook has no ownership record; no file changed".into());
    }
    let block = if state["hookVersion"] == 2 {
        format!("\n{}", include_hook(paths))
    } else {
        include_hook(paths)
    };
    crate::config_file::strip_exact(text, BEGIN, END, &block)
}

fn text_file(path: &Path) -> Result<String> {
    String::from_utf8(common::bounded_file(path, common::FILE_LIMIT)?).map_err(|e| e.to_string())
}
fn loaded(hypr: &mut impl Hypr) -> Result<bool> {
    let v: Value = serde_json::from_str(&hypr.command(&["-j", "plugin", "list"])?)
        .map_err(|_| "Hyprland returned an invalid plugin list")?;
    let list = v
        .as_array()
        .ok_or("Hyprland returned an invalid plugin list")?;
    if list.iter().any(|v| !v.is_object()) {
        return Err("Hyprland returned an invalid plugin list".into());
    }
    let count = list.iter().filter(|v| v["name"] == "hyprbars").count();
    if count > 1 {
        return Err("Multiple Hyprbars backends are loaded. Resolve the competing setups and restart Hyprland before using Familiar controls.".into());
    }
    Ok(count == 1)
}
// A registration name or an old owner.json is not proof that a shared system
// library belongs to Familiar. Limit explicit load/unload to our private tree.
fn private_library(paths: &Paths, library: &Path) -> Result<PathBuf> {
    let root = fs::canonicalize(paths.source.join("bin/hyprbars"))
        .map_err(|_| "Familiar's private titlebar backend is missing; run setup again")?;
    let path = fs::canonicalize(library).map_err(|e| e.to_string())?;
    let source = fs::canonicalize(&paths.source).map_err(|e| e.to_string())?;
    if !root.starts_with(source.join("bin"))
        || !path.starts_with(&root)
        || path.file_name().is_none_or(|n| n != "hyprbars.so")
        || !path.is_file()
    {
        return Err("Refusing a titlebar backend outside Familiar's private installation. System and hyprpm backends belong to their existing integration.".into());
    }
    Ok(path)
}

// Core owns loading, ABI validation and workspace scope.
// We never infer ownership from the shared plugin registration name.
fn official_status(paths: &Paths, state: &Value, hypr: &mut impl Hypr) -> Result<Value> {
    if !paths.official_library.is_file() {
        return Ok(
            json!({"state":"package-missing","backend":"omarchy","message":"Omarchy's titlebar package is missing. Update Omarchy through its normal package channel. Familiar will not reactivate its old loader."}),
        );
    }
    if let Some(retired) = state["retiredSession"].as_str()
        && (paths.compositor_session.is_empty() || retired == paths.compositor_session)
    {
        return Ok(
            json!({"state":"restart-required","backend":"omarchy","message":"Familiar’s old loader is retired. Log out and back in to use your saved controls with Omarchy’s renderer."}),
        );
    }
    if checked(hypr, &["eval", "assert(o and type(o.workspace_mode) == 'function', 'Omarchy floating-workspace support is missing')"]).is_err() {
        return Ok(json!({"state":"core-required","backend":"omarchy","message":"The titlebar package is installed, but this session lacks Omarchy's floating-workspace support. Update Omarchy normally and log in again. Familiar will not load a competing backend."}));
    }
    Ok(
        json!({"state":"ready","backend":"omarchy","message":"Omarchy’s renderer is ready for Familiar controls on floating workspaces (Super+L)."}),
    )
}

/// Explicit handoff: retire our generated loader, without loading, unloading or
/// reloading the compositor. Existing private mappings retire at the next login.
/// Journal first: interruption must never let reconciliation recreate the fork.
pub fn migrate(paths: &Paths, hypr: &mut impl Hypr) -> Result<Value> {
    if !paths.official_library.is_file() {
        return Err("Install Omarchy's titlebar package through your normal Omarchy update before switching controls.".into());
    }
    let state_file = paths.directory.join("owner.json");
    let state = read_json(&state_file)?;
    let before = crate::config_file::read(&paths.config)?;
    owned_config(paths, &state, &before)?;
    let already_official = state["backend"] == "omarchy";
    let had_private = !already_official && state.as_object().is_some_and(|o| !o.is_empty());
    if had_private && paths.compositor_session.is_empty() {
        return Err("Switch controls from inside your Hyprland session so Familiar can verify the required restart.".into());
    }
    // Retain legacy ownership fields and the inert include hook for rollback
    // to versions with the official-package guard. Never change user settings.
    let mut next = state;
    next["backend"] = json!("omarchy");
    next["source"] = json!(paths.source);
    next["config"] = json!(paths.config);
    if had_private {
        next["retiredSession"] = json!(paths.compositor_session);
    }
    next["controlsVersion"] = json!(2);
    if !before.contains(BEGIN) {
        next["hookVersion"] = json!(2);
    }
    next["migrationPending"] = json!(true);
    atomic(
        &state_file,
        &serde_json::to_vec(&next).map_err(|e| e.to_string())?,
    )?;
    atomic(
        &paths.directory.join("titlebars.lua"),
        b"-- Titlebars are managed by Omarchy. Familiar does not load or configure a backend.\n",
    )?;
    if !before.contains(BEGIN) {
        crate::config_file::replace(
            &paths.config,
            &before,
            &format!("{}\n{}", before, include_hook(paths)),
            &paths.directory.join("backups"),
        )?;
    }
    next["migrationPending"] = json!(false);
    atomic(
        &state_file,
        &serde_json::to_vec(&next).map_err(|e| e.to_string())?,
    )?;
    official_status(paths, &next, hypr)
}
pub fn setup(args: &Args, paths: &Paths, hypr: &mut impl Hypr) -> Result<Value> {
    if args.install_dependency {
        return Err("Familiar no longer installs a competing hyprpm backend. Use the in-app setup; official-package migration is tracked in issue #74.".into());
    }
    let state_file = paths.directory.join("owner.json");
    let state = read_json(&state_file)?;
    if state["backend"] == "omarchy" {
        return Err(
            "Omarchy manages these controls. Familiar will not recreate a private loader.".into(),
        );
    }
    if paths.official_library.exists() {
        return Err(MIGRATION_REQUIRED.into());
    }
    if loaded(hypr)? {
        return Err("Hyprbars is already in use. Disable your existing setup before using Familiar title bars".into());
    }
    if let Some(source) = state["source"].as_str()
        && source != paths.source.to_string_lossy()
    {
        return Err("Title bars belong to another Familiar installation".into());
    }
    let original = crate::config_file::read(&paths.config)?;
    let clean = owned_config(paths, &state, &original)?;
    let settings_path = paths
        .home
        .join(".config/omarchy/familiar-desktop-settings.json");
    let mut settings = if args.enable {
        read_json(&settings_path)?
    } else {
        json!({})
    };
    let library = if let Some(p) = &args.library {
        fs::canonicalize(p).map_err(|e| e.to_string())?
    } else {
        return Err("Choose Familiar’s private backend through in-app setup; shared backends cannot be adopted.".into());
    };
    let library = private_library(paths, &library)?;
    if !loaded(hypr)? {
        checked(hypr, &["plugin", "load", &library.to_string_lossy()])?;
        let probe = checked(
            hypr,
            &[
                "eval",
                "assert(hl.plugin.hyprbars and hl.plugin.hyprbars.add_button, 'Familiar requires Hyprbars with Lua button support')",
            ],
        );
        let unload = checked(hypr, &["plugin", "unload", &library.to_string_lossy()]);
        probe?;
        unload?;
    }
    let generated = paths.directory.join("titlebars.lua");
    if !state_file.exists() {
        atomic(&generated, b"-- Familiar title bars are disabled.\n")?;
    }
    atomic(
        &state_file,
        &serde_json::to_vec(
            &json!({"library":library,"source":paths.source,"config":paths.config,"hookVersion":2}),
        )
        .map_err(|e| e.to_string())?,
    )?;
    // Include the separator in our exact owned block; never trim personal bytes.
    let hook = format!("{}\n{}", clean, include_hook(paths));
    if let Err(error) = crate::config_file::replace(
        &paths.config,
        &original,
        &hook,
        &paths.directory.join("backups"),
    ) {
        atomic(
            &state_file,
            &serde_json::to_vec(&state).map_err(|e| e.to_string())?,
        )?;
        return Err(error);
    }
    if args.enable {
        settings["titlebarsEnabled"] = json!(true);
        settings["titlebarStyle"] = json!(args.style);
        settings["titlebarMode"] = json!(args.style);
        settings["dockEnabled"] = json!(true);
        atomic(
            &settings_path,
            &serde_json::to_vec_pretty(&settings).map_err(|e| e.to_string())?,
        )?;
    }
    Ok(
        json!({"state":"ready","message":"Setup complete. Enable Window controls in Familiar Desktop."}),
    )
}
fn reconcile_official(
    args: &Args,
    paths: &Paths,
    state: &mut Value,
    config: &str,
    hypr: &mut impl Hypr,
) -> Result<Value> {
    let session = state["session"].as_str().unwrap_or("");
    let time = |s: &str| s.split('-').next().unwrap_or("").parse::<u64>().ok();
    if (args.operation == "disable" && args.if_owner && session != args.owner)
        || matches!((time(session), time(&args.owner)), (Some(a), Some(b)) if b < a)
    {
        return Ok(
            json!({"state":"off","backend":"omarchy","message":"A newer Familiar instance owns the controls."}),
        );
    }
    let status = official_status(paths, state, hypr)?;
    if status["state"] != "ready" {
        return Ok(status);
    }
    let policy = if args.operation == "disable" {
        json!({"enabled":false})
    } else {
        theme_policy(
            &read_json(
                &paths
                    .home
                    .join(".local/state/omarchy/current/theme/familiar-desktop.json"),
            )?,
            args,
        )?
    };
    let active = args.operation != "disable" && policy["enabled"] == true;
    let content = if active {
        render_official(paths, &policy)?
    } else {
        "-- Familiar styling disabled; Core supplies its normal controls.\n".into()
    };
    let generated = paths.directory.join("titlebars.lua");
    let before = text_file(&generated)?;
    let verify = |hypr: &mut _| {
        if active {
            checked(
                hypr,
                &[
                    "eval",
                    "assert(familiar_titlebars and (familiar_titlebars.state == 'active' or familiar_titlebars.state == 'ready'), 'Familiar titlebar integration: ' .. (familiar_titlebars and familiar_titlebars.state or 'hook not loaded'))",
                ],
            )?;
        }
        Ok(())
    };
    if before != content {
        crate::config_file::apply_generated(
            hypr,
            crate::config_file::GeneratedUpdate {
                config: &paths.config,
                generated: &generated,
                backups: &paths.directory.join("backups"),
                before: config,
                after: config,
                generated_before: Some(&before),
                generated_after: Some(&content),
            },
            verify,
        )?;
    } else {
        verify(hypr)?;
    }
    state["session"] = json!(args.owner);
    atomic(
        &paths.directory.join("owner.json"),
        &serde_json::to_vec(state).map_err(|e| e.to_string())?,
    )?;
    Ok(
        json!({"state":if active {"configured"} else {"managed"},"backend":"omarchy","message":if active {"Familiar controls are configured for Omarchy’s floating workspaces (Super+L). Minimise restores from the dock."} else {"Omarchy’s default titlebar controls are active. Familiar’s saved style is unchanged."}}),
    )
}

pub fn reconcile(args: &Args, paths: &Paths, hypr: &mut impl Hypr) -> Result<Value> {
    let state_file = paths.directory.join("owner.json");
    let mut state = read_json(&state_file)?;
    if state["backend"] == "omarchy" {
        let text = crate::config_file::read(&paths.config)?;
        owned_config(paths, &state, &text)?;
        if state["migrationPending"] == true
            || state["controlsVersion"] != 2
            || !text.contains(BEGIN)
        {
            return Ok(
                json!({"state":"migration-required","backend":"omarchy","message":"Choose Use Familiar controls to finish connecting your saved style to Omarchy’s renderer."}),
            );
        }
        return reconcile_official(args, paths, &mut state, &text, hypr);
    }
    if state.as_object().is_some_and(|o| o.is_empty()) {
        // Fresh installations must not offer private-backend setup on a Core
        // floating-workspace host. Presence is not proof of a loaded ABI/owner.
        if paths.official_library.exists() {
            return Ok(
                json!({"state":"migration-required","backend":"omarchy","message":MIGRATION_REQUIRED}),
            );
        }
        return Ok(
            json!({"state":"setup-required","message":"Build the Rust helper and run title-bar setup from Familiar's settings."}),
        );
    }
    if state["source"].as_str() != Some(paths.source.to_string_lossy().as_ref()) {
        return Err("Title bars belong to another Familiar installation; run setup from the installed plugin".into());
    }
    let current_config = crate::config_file::read(&paths.config)?;
    owned_config(paths, &state, &current_config)?;
    if !current_config.contains(BEGIN) {
        return Ok(
            json!({"state":"setup-required","message":"The title-bar configuration hook is missing."}),
        );
    }
    let session = state["session"].as_str().unwrap_or("");
    let token_time = |s: &str| s.split('-').next().unwrap_or("").parse::<u64>().ok();
    if (args.operation == "disable" && args.if_owner && session != args.owner)
        || matches!((token_time(session),token_time(&args.owner)),(Some(a),Some(b)) if b<a)
    {
        return Ok(json!({"state":"off","message":"A newer Familiar instance owns the controls."}));
    }
    let generated = paths.directory.join("titlebars.lua");
    if paths.official_library.exists() {
        // Retire only our generated loader. Do not reload or unload anything:
        // Hyprland 0.56.2 cannot tell us the provenance of a named backend.
        atomic(
            &generated,
            b"-- Familiar controls paused for Omarchy's titlebar package.\n",
        )?;
        return Ok(
            json!({"state":"migration-required","backend":"omarchy","message":MIGRATION_REQUIRED}),
        );
    }
    let mut active = false;
    let content = if args.operation == "disable" {
        "-- Familiar title bars are disabled.\n".into()
    } else {
        let library = PathBuf::from(
            state["library"]
                .as_str()
                .ok_or("Invalid title-bar ownership state")?,
        );
        if !library.is_file() {
            return Ok(
                json!({"state":"missing","message":"Hyprbars is missing. Run title-bar setup again."}),
            );
        }
        let library = private_library(paths, &library)?;
        let policy = (|| {
            let document = read_json(
                &paths
                    .home
                    .join(".local/state/omarchy/current/theme/familiar-desktop.json"),
            )?;
            theme_policy(&document, args)
        })();
        let policy = match policy {
            Ok(v) => v,
            Err(e) => {
                atomic(
                    &generated,
                    b"-- Title bars disabled after a theme validation error.\n",
                )?;
                checked(hypr, &["reload"])?;
                return Err(e);
            }
        };
        active = policy["enabled"] == true;
        if active {
            render(paths, &library, &policy)?
        } else {
            "-- Familiar title bars are disabled by the active theme.\n".into()
        }
    };
    state["session"] = json!(args.owner);
    atomic(
        &state_file,
        &serde_json::to_vec(&state).map_err(|e| e.to_string())?,
    )?;
    if !generated.exists() || text_file(&generated)? != content {
        atomic(&generated, content.as_bytes())?;
        if let Err(e) = checked(hypr, &["reload"]) {
            atomic(
                &generated,
                b"-- Title bars disabled after a reload failure.\n",
            )?;
            return Err(e);
        }
    }
    if active {
        let probe = (|| {
            if !loaded(hypr)? {
                return Err(
                    "Hyprbars did not load; check compatibility with your Hyprland build".into(),
                );
            }
            checked(
                hypr,
                &[
                    "eval",
                    "assert(hl.plugin.hyprbars and hl.plugin.hyprbars.add_button, 'Hyprbars Lua button support is missing')",
                ],
            )?;
            let errors = hypr.command(&["configerrors"])?;
            if !errors.trim().is_empty() {
                return Err(common::clipped(&errors));
            }
            Ok(())
        })();
        if let Err(e) = probe {
            atomic(
                &generated,
                b"-- Title bars disabled after a configuration error.\n",
            )?;
            checked(hypr, &["reload"])?;
            return Err(e);
        }
    }
    Ok(
        json!({"state":if active{"active"}else{"off"},"message":if active && args.mode=="theme"{"Window controls follow the active theme."}else if active{"Window controls are active."}else{"Window controls are off."}}),
    )
}
pub fn remove(paths: &Paths, hypr: &mut impl Hypr) -> Result<Value> {
    let state_file = paths.directory.join("owner.json");
    let state = read_json(&state_file)?;
    let before = crate::config_file::read(&paths.config)?;
    let after = owned_config(paths, &state, &before)?;
    if state.as_object().is_some_and(|o| o.is_empty()) {
        return Ok(json!({"state":"removed","message":"No Familiar title-bar hook is installed."}));
    }
    if state["backend"] == "omarchy" {
        let generated = paths.directory.join("titlebars.lua");
        let previous = text_file(&generated).ok();
        // A still-mapped private backend must retire at logout, never by an
        // automatic reload. Otherwise removing our adapter restores Core now.
        let retired = state["retiredSession"].as_str().is_some_and(|session| {
            paths.compositor_session.is_empty() || session == paths.compositor_session
        });
        if retired || !paths.official_library.is_file() {
            crate::config_file::replace(
                &paths.config,
                &before,
                &after,
                &paths.directory.join("backups"),
            )?;
            atomic(&generated, b"-- Familiar controls removed.\n")?;
        } else {
            crate::config_file::apply_generated(
                hypr,
                crate::config_file::GeneratedUpdate {
                    config: &paths.config,
                    generated: &generated,
                    backups: &paths.directory.join("backups"),
                    before: &before,
                    after: &after,
                    generated_before: previous.as_deref(),
                    generated_after: None,
                },
                |_| Ok(()),
            )?;
        }
        // Preserve the delegation receipt: reinstall/re-enable must not silently
        // resurrect the private backend if the system package disappears.
        return Ok(
            json!({"state":"removed","message":"Familiar's hook is removed. Omarchy's package, configuration and saved preferences were left intact."}),
        );
    }
    let library = state["library"]
        .as_str()
        .ok_or("Invalid title-bar ownership state")?;
    // Validate before editing the hook or issuing an unload. Never trust a
    // stale/manually altered ownership receipt naming a shared package.
    let library = private_library(paths, Path::new(library))?;
    let backups = paths.directory.join("backups");
    crate::config_file::replace(&paths.config, &before, &after, &backups)?;
    let cleanup = (|| {
        if paths.official_library.exists() {
            // Removing our hook must not disrupt the shared package. A future
            // compositor reload/restart will retire any old Familiar loader.
            return Ok(());
        }
        if loaded(hypr)? {
            checked(hypr, &["plugin", "unload", &library.to_string_lossy()])?;
        }
        checked(hypr, &["reload"])?;
        let errors = hypr.command(&["configerrors"])?;
        if !errors.trim().is_empty() {
            return Err(common::clipped(&errors));
        }
        // A remaining named backend can belong to Core. Its presence is not
        // a reason to restore Familiar's loader or unload the shared backend.
        Ok(())
    })();
    if let Err(error) = cleanup {
        crate::config_file::replace(&paths.config, &after, &before, &backups)?;
        let recovery = checked(hypr, &["reload"]);
        return Err(format!(
            "{error}. Previous title-bar hook restored; recovery reload: {}",
            recovery.err().unwrap_or_else(|| "ok".into())
        ));
    }
    for p in [paths.directory.join("titlebars.lua"), state_file] {
        match fs::remove_file(p) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(e.to_string()),
        }
    }
    Ok(
        json!({"state":"removed","message":if paths.official_library.exists() {"Familiar's hook was removed. No shared backend was unloaded. Restart Hyprland to retire any old Familiar backend."} else {"Familiar's title-bar hook was removed."}}),
    )
}

pub fn window_action(name: &str, hypr: &mut impl Hypr) -> Result<Value> {
    window_action_at(name, "", hypr)
}

pub fn window_action_at(name: &str, target: &str, hypr: &mut impl Hypr) -> Result<Value> {
    if !["close", "minimize", "maximize"].contains(&name) {
        return Err("Unknown window action".into());
    }
    let client: Value = if target.is_empty() {
        serde_json::from_str(&hypr.command(&["-j", "activewindow"])?)
            .map_err(|_| "Hyprland returned invalid window information")?
    } else {
        json!({"address":target})
    };
    let address = client["address"].as_str().ok_or("No active window")?;
    if !crate::dock::valid_address(address) {
        return Err("No active window".into());
    }
    if name == "minimize" {
        crate::dock::execute("minimize-instance", &[address.to_string()])?;
    } else {
        let dispatch = if name == "close" {
            format!(
                "hl.dsp.window.close({{ window = {} }})",
                lua(&format!("address:{address}"))
            )
        } else {
            format!(
                "hl.dsp.window.fullscreen({{ window = {}, mode = 'maximized', action = 'toggle' }})",
                lua(&format!("address:{address}"))
            )
        };
        checked(hypr, &["dispatch", &dispatch])?;
    }
    Ok(json!({"state":"ok"}))
}
pub fn execute(argv: &[String]) -> Result<Value> {
    let args = Args::parse(argv)?;
    let paths = Paths::system()?;
    let mut hypr = common::SystemHypr;
    if args.operation == "action" {
        return window_action_at(&args.action, &args.window, &mut hypr);
    }
    let _lock = common::lock(&paths.directory.join("lock"))?;
    match args.operation.as_str() {
        "setup" => setup(&args, &paths, &mut hypr),
        "migrate" => migrate(&paths, &mut hypr),
        "remove" => remove(&paths, &mut hypr),
        _ => reconcile(&args, &paths, &mut hypr),
    }
}
