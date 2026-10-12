const KNOWN_CLI_COMMANDS: &[&str] = &[
    "yazi",
    "nvim",
    "neovim",
    "vim",
    "nano",
    "micro",
    "helix",
    "hx",
    "emacs",
    "kakoune",
    "kak",
    "amp",
    "btop",
    "htop",
    "top",
    "bottom",
    "btm",
    "glances",
    "bashtop",
    "bpytop",
    "nvtop",
    "gotop",
    "ranger",
    "superfile",
    "broot",
    "vifm",
    "nnn",
    "lf",
    "fff",
    "mc",
    "midnight-commander",
    "clifm",
    "lazygit",
    "lazydocker",
    "tig",
    "gitui",
    "k9s",
    "ox",
    "bandwhich",
    "gping",
    "ncmpcpp",
    "cmus",
    "mocp",
    "cava",
    "cliamp",
    "rmpc",
    "spotify-tui",
    "spt",
    "mopidy",
    "musikcube",
    "weechat",
    "irssi",
    "profanity",
    "neomutt",
    "mutt",
    "aerc",
    "gomuks",
    "senpai",
    "tmux",
    "zellij",
    "cmatrix",
    "pipes.sh",
    "fastfetch",
    "neofetch",
    "cbonsai",
    "tty-clock",
    "peaclock",
    "termshark",
    "glow",
    "curseofwar",
];
const KNOWN_TERMINALS: &[&str] = &[
    "foot",
    "footclient",
    "kitty",
    "alacritty",
    "org.alacritty",
    "ghostty",
    "com.mitchellh.ghostty",
    "wezterm",
    "wezterm-gui",
    "org.wezfurlong.wezterm",
    "gnome-terminal",
    "org.gnome.terminal",
    "konsole",
    "org.kde.konsole",
    "xfce4-terminal",
    "tilix",
    "com.gexperts.tilix",
    "xterm",
    "uxterm",
    "urxvt",
    "rxvt",
    "rxvt-unicode",
    "termite",
    "terminator",
    "lxterminal",
    "st",
    "simple-terminal",
    "rio",
    "contour",
    "blackbox",
    "com.raggesilver.blackbox",
    "ptyxis",
    "org.gnome.ptyxis",
    "tabby",
    "hyper",
    "warp",
    "warp-terminal",
];
use crate::{
    Result,
    common::{self, lua},
};
use serde_json::{Value, json};
use std::{
    env, fs,
    io::{Read, Write},
    os::unix::io::FromRawFd,
    os::unix::net::UnixStream,
    os::unix::process::CommandExt,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{Duration, Instant},
};

pub fn valid_address(s: &str) -> bool {
    s.len() > 2 && s.starts_with("0x") && s[2..].bytes().all(|b| b.is_ascii_hexdigit())
}
pub fn normalize(s: &str) -> String {
    let mut s = s.trim().to_lowercase();
    for tail in [".desktop", ".exe"] {
        if s.ends_with(tail) {
            s.truncate(s.len() - tail.len());
        }
    }
    for prefix in ["org.", "com.", "net.", "io."] {
        s = s.replace(prefix, "");
    }
    s.chars().filter(|c| c.is_alphanumeric()).collect()
}
pub fn is_terminal(s: &str) -> bool {
    let raw = s.trim().to_lowercase();
    let raw = raw.strip_suffix(".desktop").unwrap_or(&raw);
    let candidates = [
        normalize(raw),
        normalize(raw.rsplit('.').next().unwrap_or(raw)),
    ];
    KNOWN_TERMINALS.iter().any(|term| {
        candidates
            .iter()
            .any(|c| !c.is_empty() && *c == normalize(term))
    })
}
fn cli_alias(s: &str) -> &str {
    match s {
        "neovim" | "vim" => "nvim",
        "hx" => "helix",
        "btm" => "bottom",
        _ => s,
    }
}
fn tokens(s: &str) -> Vec<&str> {
    s.split(|c: char| c.is_whitespace() || ":,-_/\\()[]{}|\0".contains(c))
        .filter(|s| !s.is_empty())
        .collect()
}
fn known_cli(s: &str) -> String {
    let raw = s.to_lowercase();
    tokens(&raw)
        .iter()
        .find(|t| KNOWN_CLI_COMMANDS.contains(t) && !is_terminal(t))
        .map(|s| cli_alias(s).to_string())
        .unwrap_or_default()
}
pub fn extract_cli(title: &str, pid: Option<u64>) -> String {
    if let Some(pid) = pid.filter(|p| *p > 0) {
        let root = PathBuf::from(format!("/proc/{pid}"));
        let read = |p: &Path| {
            common::bounded_file(p, 65536)
                .map(|b| String::from_utf8_lossy(&b).into_owned())
                .unwrap_or_default()
        };
        let app = known_cli(&read(&root.join("cmdline")));
        if !app.is_empty() {
            return app;
        }
        for child in read(&root.join(format!("task/{pid}/children")))
            .split_whitespace()
            .take(64)
        {
            if !child.bytes().all(|b| b.is_ascii_digit()) {
                continue;
            }
            let croot = PathBuf::from(format!("/proc/{child}"));
            for file in ["comm", "cmdline"] {
                let app = known_cli(&read(&croot.join(file)));
                if !app.is_empty() {
                    return app;
                }
            }
            for grand in read(&croot.join(format!("task/{child}/children")))
                .split_whitespace()
                .take(64)
            {
                if !grand.bytes().all(|b| b.is_ascii_digit()) {
                    continue;
                }
                let app = known_cli(&read(&PathBuf::from(format!("/proc/{grand}/comm"))));
                if !app.is_empty() {
                    return app;
                }
            }
        }
    }
    let app = known_cli(title);
    if !app.is_empty() {
        return app;
    }
    if title.to_lowercase().contains("whips") || title.to_lowercase().contains("terminal's ass") {
        return "cliamp".into();
    }
    String::new()
}
pub fn split_queries(queries: &[String]) -> (Vec<String>, Option<usize>, String) {
    let mut identifiers = Vec::new();
    let mut index = None;
    let mut address = String::new();
    for q in queries {
        if let Some(s) = q.strip_prefix("--index=") {
            index = s.parse().ok();
        } else if q.bytes().all(|b| b.is_ascii_digit()) && index.is_none() {
            index = q.parse().ok();
        } else if q.to_lowercase().starts_with("0x") && address.is_empty() {
            address = q.to_lowercase();
        } else {
            identifiers.push(q.clone());
        }
    }
    (identifiers, index, address)
}
pub fn exec_argv(input: &str) -> Vec<String> {
    let mut filtered = String::new();
    let mut chars = input.chars();
    while let Some(c) = chars.next() {
        if c == '%' {
            match chars.next() {
                Some('%') => filtered.push('%'),
                Some(n) if n.is_ascii_alphabetic() => {}
                Some(n) => {
                    filtered.push('%');
                    filtered.push(n);
                }
                None => filtered.push('%'),
            }
        } else {
            filtered.push(c);
        }
    }
    let mut args = Vec::new();
    let mut token = String::new();
    let mut quote = None;
    let mut escape = false;
    let mut started = false;
    for c in filtered.chars() {
        if escape {
            token.push(c);
            escape = false;
            started = true;
            continue;
        }
        if c == '\\' && quote != Some('\'') {
            escape = true;
            started = true;
            continue;
        }
        if let Some(q) = quote {
            if c == q {
                quote = None;
            } else {
                token.push(c);
            }
            started = true;
        } else if c == '"' || c == '\'' {
            quote = Some(c);
            started = true;
        } else if c.is_whitespace() {
            if started {
                args.push(std::mem::take(&mut token));
                started = false;
            }
        } else {
            token.push(c);
            started = true;
        }
    }
    if quote.is_some() || escape {
        return Vec::new();
    }
    if started {
        args.push(token);
    }
    args
}
pub fn match_pwa(class: &str, query: &str) -> bool {
    let class = class.to_lowercase();
    if ![
        "chrome-",
        "chromium-",
        "brave-",
        "edge-",
        "msedge-",
        "microsoft-edge-",
    ]
    .iter()
    .any(|p| class.starts_with(p))
    {
        return false;
    }
    let args = exec_argv(query);
    let option = |key: &str| {
        args.iter()
            .find_map(|a| a.strip_prefix(key).map(str::to_string))
    };
    if let Some(profile) = option("--profile-directory=")
        && !class.ends_with(&format!("-{}", profile.replace(' ', "_").to_lowercase()))
    {
        return false;
    }
    if let Some(raw) = option("--app=")
        && let Ok(url) = url::Url::parse(&raw)
    {
        let host = url.host_str().unwrap_or("").to_lowercase();
        if host.is_empty() {
            return false;
        }
        let path = url.path();
        let key = format!("{}_{}", host, path.replace('/', "_"));
        let alt = format!("{}_{}", host, path.trim_end_matches('/').replace('/', "_"));
        return class.contains(&key) || class.contains(&alt);
    }
    option("--app-id=").is_some_and(|id| !id.is_empty() && class.contains(&id.to_lowercase()))
}
fn application_dirs(home: &Path) -> Vec<PathBuf> {
    let mut dirs = vec![
        home.join(".local/share/applications"),
        "/usr/share/applications".into(),
        "/usr/local/share/applications".into(),
        "/var/lib/flatpak/exports/share/applications".into(),
        home.join(".local/share/flatpak/exports/share/applications"),
    ];
    for dir in env::split_paths(&env::var_os("XDG_DATA_DIRS").unwrap_or_default()) {
        if !dir.as_os_str().is_empty() {
            let dir = dir.join("applications");
            if !dirs.contains(&dir) {
                dirs.push(dir);
            }
        }
    }
    dirs
}
pub fn find_desktop(id: &str, dirs: &[PathBuf]) -> Option<String> {
    if id.is_empty()
        || id.starts_with('-')
        || id.contains('/')
        || id.contains('\0')
        || id == "."
        || id == ".."
    {
        return None;
    }
    let mut names = vec![format!("{id}.desktop")];
    if id.ends_with(".desktop") {
        names.push(id.into());
    }
    for dir in dirs {
        for name in &names {
            if dir.join(name).is_file() {
                return Some(name.clone());
            }
        }
    }
    None
}
fn spawn(program: &str, args: &[String]) -> bool {
    Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .is_ok()
}
fn executable(program: &str) -> bool {
    if program.contains('/') {
        return Path::new(program).is_file();
    }
    env::split_paths(&env::var_os("PATH").unwrap_or_default()).any(|d| d.join(program).is_file())
}
pub fn launch(queries: &[String]) -> Result<()> {
    let dirs = application_dirs(&common::home()?);
    for q in queries
        .iter()
        .filter(|q| !q.starts_with("0x") && !q.starts_with("--"))
    {
        if ["cliamp", "org.omarchy.cliamp"].contains(
            &q.trim()
                .trim_end_matches(".desktop")
                .to_lowercase()
                .as_str(),
        ) && spawn(
            "foot",
            &["-a", "cliamp", "-T", "cliamp", "-e", "cliamp"].map(str::to_string),
        ) {
            return Ok(());
        }
        if let Some(id) = find_desktop(q, &dirs)
            && (spawn("uwsm-app", &["--".into(), "gtk-launch".into(), id.clone()])
                || spawn("gtk-launch", &[id]))
        {
            return Ok(());
        }
    }
    for q in queries
        .iter()
        .filter(|q| !q.starts_with("0x") && !q.starts_with("--"))
    {
        let argv = exec_argv(q);
        if let Some(program) = argv.first()
            && !program.starts_with('-')
            && executable(program)
        {
            let mut wrapped = vec!["--".into()];
            wrapped.extend(argv.clone());
            if spawn("uwsm-app", &wrapped) || spawn(program, &argv[1..]) {
                return Ok(());
            }
        }
    }
    Err("Could not launch this application".into())
}
pub fn scan_icons(bases: &[PathBuf]) -> Value {
    let subdirs = [
        "hicolor/scalable/apps",
        "hicolor/scalable/devices",
        "hicolor/256x256/apps",
        "hicolor/128x128/apps",
        "hicolor/48x48/apps",
        "hicolor/32x32/apps",
        "hicolor/16x16/apps",
        "scalable/apps",
        "scalable/devices",
    ];
    let mut png = serde_json::Map::new();
    let mut svg = serde_json::Map::new();
    let mut count = 0;
    for base in bases {
        for sub in subdirs.into_iter().chain([""]) {
            if let Ok(entries) = fs::read_dir(base.join(sub)) {
                for entry in entries.flatten() {
                    count += 1;
                    if count > 50000 {
                        break;
                    }
                    let path = entry.path();
                    let Some(name) = path
                        .file_name()
                        .and_then(|s| s.to_str())
                        .map(str::to_lowercase)
                    else {
                        continue;
                    };
                    if !path.is_file() {
                        continue;
                    }
                    let map = if name.ends_with(".svg") {
                        &mut svg
                    } else if name.ends_with(".png") {
                        &mut png
                    } else {
                        continue;
                    };
                    let key = name[..name.len() - 4].to_string();
                    map.entry(key).or_insert(json!(path));
                }
            }
        }
    }
    png.extend(svg);
    let mut extras = serde_json::Map::new();
    for (k, v) in &png {
        if let Some((_, suffix)) = k.rsplit_once('.')
            && !suffix.is_empty()
            && !png.contains_key(suffix)
        {
            extras.entry(suffix.to_string()).or_insert(v.clone());
        }
    }
    png.extend(extras);
    Value::Object(png)
}
fn icon_bases(home: &Path) -> Vec<PathBuf> {
    let mut dirs = vec![
        home.join(".local/share/icons"),
        home.join(".icons"),
        "/usr/local/share/icons".into(),
        "/usr/share/icons".into(),
        "/usr/share/pixmaps".into(),
        "/usr/local/share/pixmaps".into(),
    ];
    for d in env::split_paths(&env::var_os("XDG_DATA_DIRS").unwrap_or_default()) {
        if !d.as_os_str().is_empty() {
            let d = d.join("icons");
            if !dirs.contains(&d) {
                dirs.push(d);
            }
        }
    }
    dirs
}
pub fn get_socket() -> Result<PathBuf> {
    let runtime = env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(format!("/run/user/{}", unsafe { libc::getuid() })));
    if let Ok(sig) = env::var("HYPRLAND_INSTANCE_SIGNATURE") {
        if sig.contains('/') || sig == "." || sig == ".." {
            return Err("Invalid Hyprland session signature".into());
        }
        let path = runtime.join("hypr").join(sig).join(".socket.sock");
        if path.exists() {
            return Ok(path);
        }
    }
    if let Ok(entries) = fs::read_dir(runtime.join("hypr")) {
        for entry in entries.flatten() {
            let p = entry.path().join(".socket.sock");
            if p.exists() {
                return Ok(p);
            }
        }
    }
    Err("Hyprland socket is unavailable".into())
}
pub fn socket_command(path: &Path, cmd: &str, timeout: Duration, limit: usize) -> Result<String> {
    let raw = path.as_os_str().as_encoded_bytes();
    // SAFETY: sockaddr_un is a plain C structure; initialize every byte before use.
    let mut addr: libc::sockaddr_un = unsafe { std::mem::zeroed() };
    if raw.len() >= addr.sun_path.len() {
        return Err("Socket path is too long".into());
    }
    addr.sun_family = libc::AF_UNIX as _;
    for (i, b) in raw.iter().enumerate() {
        addr.sun_path[i] = *b as _;
    }
    // SAFETY: create a fresh descriptor, transferring ownership exactly once below.
    let fd = unsafe {
        libc::socket(
            libc::AF_UNIX,
            libc::SOCK_STREAM | libc::SOCK_NONBLOCK | libc::SOCK_CLOEXEC,
            0,
        )
    };
    if fd < 0 {
        return Err(std::io::Error::last_os_error().to_string());
    }
    let mut stream = unsafe { UnixStream::from_raw_fd(fd) };
    let deadline = Instant::now() + timeout;
    let result = unsafe {
        libc::connect(
            fd,
            (&addr as *const libc::sockaddr_un).cast(),
            std::mem::size_of_val(&addr) as _,
        )
    };
    if result < 0 {
        let e = std::io::Error::last_os_error();
        if !matches!(e.raw_os_error(), Some(libc::EINPROGRESS | libc::EAGAIN)) {
            return Err(e.to_string());
        }
        let mut p = libc::pollfd {
            fd,
            events: libc::POLLOUT,
            revents: 0,
        };
        let ready =
            unsafe { libc::poll(&mut p, 1, timeout.as_millis().min(i32::MAX as u128) as i32) };
        if ready <= 0 {
            return Err("Hyprland socket timed out".into());
        }
        if let Some(e) = stream.take_error().map_err(|e| e.to_string())? {
            return Err(e.to_string());
        }
    }
    stream.set_nonblocking(false).map_err(|e| e.to_string())?;
    stream
        .set_write_timeout(Some(
            deadline
                .saturating_duration_since(Instant::now())
                .max(Duration::from_millis(1)),
        ))
        .map_err(|e| e.to_string())?;
    stream
        .write_all(cmd.as_bytes())
        .map_err(|e| e.to_string())?;
    let mut data = Vec::new();
    let mut buf = [0u8; 4096];
    loop {
        let remaining = deadline
            .checked_duration_since(Instant::now())
            .ok_or("Hyprland socket timed out")?;
        stream
            .set_read_timeout(Some(remaining))
            .map_err(|e| e.to_string())?;
        let n = stream.read(&mut buf).map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        if data.len() + n > limit {
            return Err("Hyprland response exceeded its byte limit".into());
        }
        data.extend_from_slice(&buf[..n]);
    }
    String::from_utf8(data).map_err(|e| e.to_string())
}
pub trait DockIpc {
    fn command(&mut self, cmd: &str) -> Result<String>;
}
struct SocketIpc(PathBuf);
impl DockIpc for SocketIpc {
    fn command(&mut self, cmd: &str) -> Result<String> {
        socket_command(&self.0, cmd, Duration::from_secs(2), 8 * 1024 * 1024)
    }
}
fn address(c: &Value) -> &str {
    c["address"].as_str().unwrap_or("")
}
fn workspace(c: &Value) -> &str {
    c["workspace"]["name"].as_str().unwrap_or("")
}
fn hidden(c: &Value) -> bool {
    workspace(c).starts_with("special:")
}
pub fn pick_target<'a>(
    matching: &[&'a Value],
    all: &'a [Value],
    address_arg: &str,
    index: Option<usize>,
    active: &str,
) -> Option<&'a Value> {
    if !address_arg.is_empty()
        && let Some(c) = matching
            .iter()
            .copied()
            .chain(all.iter())
            .find(|c| address(c).eq_ignore_ascii_case(address_arg))
    {
        return Some(c);
    }
    if let Some(c) = index.and_then(|n| matching.get(n)) {
        return Some(*c);
    }
    if !active.is_empty()
        && let Some(c) = matching
            .iter()
            .find(|c| address(c).eq_ignore_ascii_case(active))
    {
        return Some(*c);
    }
    matching
        .iter()
        .find(|c| !hidden(c))
        .or_else(|| matching.first())
        .copied()
}
fn dispatch(ipc: &mut impl DockIpc, cmd: String) -> Result<()> {
    let response = ipc.command(&cmd)?;
    if response.trim().eq_ignore_ascii_case("ok") {
        Ok(())
    } else {
        Err(common::clipped(&response))
    }
}
fn focus(ipc: &mut impl DockIpc, addr: &str) -> Result<()> {
    if !valid_address(addr) {
        return Err("Invalid window address".into());
    }
    dispatch(
        ipc,
        format!(
            "dispatch hl.dsp.focus({{ window = {} }})",
            lua(&format!("address:{addr}"))
        ),
    )
}
fn focus_and_point(ipc: &mut impl DockIpc, addr: &str) -> Result<()> {
    focus(ipc, addr)?;
    let selector = lua(&format!("address:{addr}"));
    // Query goal geometry after restore/focus, not stale pre-move coordinates.
    // Hyprland uses logical global coordinates, including scaled/negative outputs.
    dispatch(
        ipc,
        format!(
            "dispatch hl.dsp.cursor.move({{ x = hl.get_window({selector}).at.x + hl.get_window({selector}).size.x / 2, y = hl.get_window({selector}).at.y + hl.get_window({selector}).size.y / 2 }})"
        ),
    )
}
fn move_window(ipc: &mut impl DockIpc, addr: &str, ws: &str, follow: bool) -> Result<()> {
    if !valid_address(addr) {
        return Err("Invalid window address".into());
    }
    dispatch(
        ipc,
        format!(
            "dispatch hl.dsp.window.move({{ window = {}, workspace = {}, follow = {follow} }})",
            lua(&format!("address:{addr}")),
            lua(ws)
        ),
    )
}
fn close_special(ipc: &mut impl DockIpc, monitors: &[Value]) -> Result<()> {
    for m in monitors {
        if let Some(name) = m["specialWorkspace"]["name"]
            .as_str()
            .filter(|s| !s.is_empty())
        {
            dispatch(
                ipc,
                format!(
                    "dispatch hl.dsp.workspace.toggle_special({{ workspace = {} }})",
                    lua(name.trim_start_matches("special:"))
                ),
            )?;
        }
    }
    Ok(())
}
pub fn operate(
    mode: &str,
    queries: &[String],
    clients: &[Value],
    monitors: &[Value],
    active: &str,
    ipc: &mut impl DockIpc,
) -> Result<bool> {
    let (queries, index, target) = split_queries(queries);
    if !target.is_empty() && !valid_address(&target) {
        return Err("Invalid window address".into());
    }
    let target_cli = queries
        .iter()
        .map(|q| extract_cli(q, None))
        .find(|s| !s.is_empty())
        .unwrap_or_default();
    let terminal_query = target_cli.is_empty() && queries.first().is_some_and(|q| is_terminal(q));
    let matching: Vec<&Value> = clients
        .iter()
        .filter(|c| {
            if !target.is_empty() && address(c).eq_ignore_ascii_case(&target) {
                return true;
            }
            let class = c["class"].as_str().unwrap_or("");
            let init = c["initialClass"].as_str().unwrap_or("");
            let terminal = is_terminal(class) || is_terminal(init);
            let cli = if terminal {
                extract_cli(c["title"].as_str().unwrap_or(""), c["pid"].as_u64())
            } else {
                String::new()
            };
            if !target_cli.is_empty() {
                if cli == target_cli {
                    return true;
                }
                if terminal {
                    return false;
                }
            }
            if terminal_query && !cli.is_empty() {
                return false;
            }
            queries.iter().any(|q| {
                q.eq_ignore_ascii_case(class)
                    || q.eq_ignore_ascii_case(init)
                    || (!normalize(q).is_empty()
                        && (normalize(q) == normalize(class) || normalize(q) == normalize(init)))
                    || match_pwa(class, q)
            })
        })
        .collect();
    let target = pick_target(
        &matching,
        clients,
        &target,
        index,
        if matches!(
            mode,
            "minimize"
                | "minimize-instance"
                | "toggle"
                | "toggle-instance"
                | "toggle-active"
                | "toggle-or-cycle"
        ) {
            active
        } else {
            ""
        },
    );
    let Some(target) = target else {
        return Ok(false);
    };
    let addr = address(target);
    let ws = monitors
        .iter()
        .find(|m| m["focused"] == true)
        .map(|m| {
            m["activeWorkspace"]["name"]
                .as_str()
                .map(str::to_string)
                .unwrap_or_else(|| m["activeWorkspace"]["id"].to_string())
        })
        .unwrap_or_else(|| "1".into());
    let ws = if ws.is_empty() || ws == "null" || ws.starts_with("special:") {
        "1"
    } else {
        &ws
    };
    let minimize = matches!(mode, "minimize" | "minimize-instance");
    let toggle = matches!(
        mode,
        "toggle" | "toggle-instance" | "toggle-active" | "toggle-or-cycle"
    );
    if hidden(target) {
        if minimize {
            return Ok(true);
        }
        move_window(ipc, addr, ws, true)?;
        close_special(ipc, monitors)?;
        focus_and_point(ipc, addr)?;
    } else if minimize || toggle {
        // Following this move would open the shared workspace and expose minimized windows.
        move_window(ipc, addr, "special:minimized", false)?;
        close_special(ipc, monitors)?;
        if let Some(next) = matching
            .iter()
            .copied()
            .find(|c| address(c) != addr && !hidden(c))
            .or_else(|| {
                clients
                    .iter()
                    .find(|c| address(c) != addr && !hidden(c) && workspace(c) == ws)
            })
        {
            focus(ipc, address(next))?;
        }
    } else {
        focus_and_point(ipc, addr)?;
    }
    Ok(true)
}
// Explicit per-window actions never fall back to another client or launch an app.
pub fn arrange(
    mode: &str,
    addr: &str,
    clients: &[Value],
    monitors: &[Value],
    ipc: &mut impl DockIpc,
) -> Result<()> {
    if !valid_address(addr) {
        return Err("Select a window with a valid address".into());
    }
    let c = clients
        .iter()
        .find(|c| address(c).eq_ignore_ascii_case(addr))
        .ok_or("That window has closed")?;
    let selector = lua(&format!("address:{addr}"));
    let focused = monitors
        .iter()
        .find(|m| m["focused"] == true)
        .ok_or("No focused monitor")?;
    if mode == "bring-here" || (mode == "go-window" && hidden(c)) {
        let ws = focused["activeWorkspace"]["name"]
            .as_str()
            .filter(|s| !s.is_empty() && !s.starts_with("special:"))
            .ok_or("No regular workspace")?;
        move_window(ipc, addr, ws, true)?;
        return focus_and_point(ipc, addr);
    }
    if mode == "go-window" {
        return focus_and_point(ipc, addr);
    }
    if hidden(c) {
        return Err("Restore this window before arranging it".into());
    }
    let monitor = monitors
        .iter()
        .find(|m| m["id"] == c["monitor"])
        .ok_or("Window monitor unavailable")?;
    let mut commands = Vec::new();
    match mode {
        "arrange-maximize" => commands.push(format!(
            "fullscreen({{window={selector}, mode='maximized', action='set'}})"
        )),
        "arrange-next-monitor" => {
            let next = monitors
                .iter()
                .position(|m| m["id"] == monitor["id"])
                .unwrap_or(0);
            if monitors.len() < 2 {
                return Err("Connect another monitor first".into());
            }
            let name = monitors[(next + 1) % monitors.len()]["name"]
                .as_str()
                .ok_or("Invalid monitor name")?;
            commands.push(format!(
                "move({{window={selector}, monitor={}, follow=true}})",
                lua(name)
            ));
        }
        "arrange-tile" | "arrange-float" | "arrange-center" | "arrange-left" | "arrange-right" => {
            // Compute geometry before sending any mutation, including malformed-output checks.
            let mut geometry = None;
            if matches!(mode, "arrange-left" | "arrange-right") {
                let scale = monitor["scale"]
                    .as_f64()
                    .filter(|s| s.is_finite() && *s > 0.0)
                    .ok_or("Invalid monitor scale")?;
                let mut w = monitor["width"].as_f64().ok_or("Invalid monitor width")? / scale;
                let mut h = monitor["height"].as_f64().ok_or("Invalid monitor height")? / scale;
                if monitor["transform"].as_i64().unwrap_or(0) % 2 != 0 {
                    std::mem::swap(&mut w, &mut h);
                }
                let r = |i: usize| monitor["reserved"][i].as_f64().unwrap_or(0.0);
                let x = monitor["x"].as_f64().ok_or("Invalid monitor position")? + r(0);
                let y = monitor["y"].as_f64().ok_or("Invalid monitor position")? + r(1);
                w -= r(0) + r(2);
                h -= r(1) + r(3);
                if w < 200.0 || h < 100.0 {
                    return Err("Monitor work area is too small".into());
                }
                let left = (w / 2.0).floor();
                geometry = Some((
                    if mode == "arrange-left" { x } else { x + left },
                    y,
                    if mode == "arrange-left" {
                        left
                    } else {
                        w - left
                    },
                    h,
                ));
            }
            commands.push(format!(
                "fullscreen_state({{window={selector}, internal=0, client=0, action='set'}})"
            ));
            commands.push(format!(
                "float({{window={selector}, action='{}'}})",
                if mode == "arrange-tile" {
                    "unset"
                } else {
                    "set"
                }
            ));
            if mode == "arrange-center" {
                commands.push(format!("center({{window={selector}}})"));
            }
            if let Some((x, y, w, h)) = geometry {
                commands.push(format!(
                    "resize({{window={selector}, x={}, y={}}})",
                    w.round() as i64,
                    h.round() as i64
                ));
                commands.push(format!(
                    "move({{window={selector}, x={}, y={}}})",
                    x.round() as i64,
                    y.round() as i64
                ));
            }
        }
        _ => return Err("Unknown window arrangement".into()),
    }
    for command in commands {
        dispatch(ipc, format!("dispatch hl.dsp.window.{command}"))?;
    }
    focus(ipc, addr)
}

fn open_location(target: &str) -> Result<()> {
    // A non-D-Bus file manager inherits gio's streams and process group.
    // Wait only for the opener; the application must outlive this request.
    let mut child = Command::new("gio")
        .args(["open", "--", target])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .spawn()
        .map_err(|e| e.to_string())?;
    let deadline = Instant::now() + Duration::from_secs(8);
    loop {
        if let Some(status) = child.try_wait().map_err(|e| e.to_string())? {
            return if status.success() {
                Ok(())
            } else {
                Err(format!("Folder opener failed: {status}"))
            };
        }
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            return Err("Folder opener timed out".into());
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

pub fn execute(mode: &str, queries: &[String]) -> Result<Value> {
    if mode == "open-location" {
        if queries.len() != 1 {
            return Err("Provide exactly one file shortcut".into());
        }
        let target = match queries.first().map(String::as_str) {
            Some("home") => {
                let home = common::home()?;
                if !home.is_absolute() || !home.is_dir() {
                    return Err("Home folder is unavailable".into());
                }
                home.to_string_lossy().into_owned()
            }
            Some("downloads") => {
                let path =
                    common::run("xdg-user-dir", &["DOWNLOAD".into()], Duration::from_secs(3))?;
                let path = path.trim();
                if !PathBuf::from(path).is_absolute() || !PathBuf::from(path).is_dir() {
                    return Err("Downloads folder is unavailable".into());
                }
                path.to_string()
            }
            Some("trash") => "trash:///".into(),
            _ => return Err("Unknown file shortcut".into()),
        };
        open_location(&target)?;
        return Ok(json!({"state":"ok"}));
    }
    if mode == "scan-icons" {
        let v = scan_icons(&icon_bases(&common::home()?));
        if serde_json::to_vec(&v).map_err(|e| e.to_string())?.len() > common::OUTPUT_LIMIT {
            return Err("Icon scan exceeds 1 MiB".into());
        }
        return Ok(v);
    }
    if ![
        "go-window",
        "bring-here",
        "arrange-left",
        "arrange-right",
        "arrange-maximize",
        "arrange-center",
        "arrange-tile",
        "arrange-float",
        "arrange-next-monitor",
        "scan-cli",
        "minimize",
        "minimize-instance",
        "restore",
        "restore-or-launch",
        "toggle-active",
        "toggle-or-cycle",
        "toggle-instance",
        "activate-instance",
        "toggle",
        "activate",
    ]
    .contains(&mode)
    {
        return Err("Unknown dock operation".into());
    }
    let socket = match get_socket() {
        Ok(p) => p,
        Err(e) => {
            if mode == "restore-or-launch" {
                launch(queries)?;
                return Ok(json!({"state":"launched"}));
            }
            return Err(e);
        }
    };
    let mut ipc = SocketIpc(socket);
    let clients: Vec<Value> = serde_json::from_str(&ipc.command("j/clients")?)
        .map_err(|_| "Hyprland returned invalid clients")?;
    if mode == "scan-cli" {
        let mut apps = Vec::new();
        for c in &clients {
            if is_terminal(c["class"].as_str().unwrap_or("")) {
                let app = extract_cli(c["title"].as_str().unwrap_or(""), c["pid"].as_u64());
                if !app.is_empty() && !apps.contains(&app) {
                    apps.push(app);
                }
            }
        }
        return Ok(json!(apps));
    }
    let monitors: Vec<Value> = serde_json::from_str(&ipc.command("j/monitors")?)
        .map_err(|_| "Hyprland returned invalid monitors")?;
    if mode == "go-window" || mode == "bring-here" || mode.starts_with("arrange-") {
        if queries.len() != 1 {
            return Err("Provide exactly one window address".into());
        }
        arrange(mode, &queries[0], &clients, &monitors, &mut ipc)?;
        return Ok(json!({"state":"ok"}));
    }
    let active: Value = serde_json::from_str(&ipc.command("j/activewindow")?)
        .map_err(|_| "Hyprland returned invalid active window")?;
    if !operate(
        mode,
        queries,
        &clients,
        &monitors,
        address(&active),
        &mut ipc,
    )? && matches!(
        mode,
        "activate-instance" | "activate" | "restore" | "restore-or-launch"
    ) {
        launch(queries)?;
        return Ok(json!({"state":"launched"}));
    }
    Ok(json!({"state":"ok"}))
}
