# Official titlebars — issue #74

On `dev/v0.1.6`, Familiar's Mac/Windows controls use Omarchy's official renderer.
This supersedes the earlier native-only handoff which left those styles inactive.
No release or desktop acceptance is implied.

`integration/v0.1.6-arm-titlebars` combines this work with k-kostin's native ARM
development contribution (#85). Official-host builds contain only the
architecture-matched Familiar backend; CI now provides a static ARM development
bundle as well as the local build path. Private-host builds still need a matching
library/ABI pair, built locally on ARM. Both support first-run setup and rollback;
ordinary prebuilt ARM release installation remains separate. See [development setup](DEVELOPMENT.md).

## What changes

In **Windows → Window controls**, choose **Use Familiar controls**, then Mac,
Windows or Theme. Familiar keeps close/minimise/maximise, button alignment,
traffic-light colours, hover symbols, size, font, theme and app exclusions.
Minimised windows restore through the existing dock. Every action, including
double-click, carries the clicked window's `%WINDOW%` address; a focus change
cannot retarget it. The stock renderer uses `×`, `−`, `+` and `□` glyphs with
round/rounded-square buttons, not the old fork's Cairo vector icons.

Core still owns which workspaces float, its window tags, shadows, opacity and
loading `/usr/lib/omarchy-hyprland-titlebars/titlebars.so`. Familiar does not load
or unload a backend, change workspace modes, or edit Core/package files. Controls
follow Core's floating-workspace scope (Super+L), not every tiled window.
Choosing **Omarchy**, disabling Familiar, or an unconfigured Theme restores Core's
normal controls. This choice retains the stored `off` value for backward
compatibility; it does not disable Core's own bars. Saved preferences survive.

## Configuration contract

The reference is Core [#14482](https://github.com/omacom/omarchy/pull/14482), commit
`14987189695a8ae1f2270262fdf77446fafb1ba3`, merged 11 October 2026, and the official
renderer [v0.2.1](https://github.com/omacom/omarchy-hyprland-titlebars/tree/v0.2.1)
packaged by [#964](https://github.com/omacom/omarchy-pkgs/pull/964). This renderer
defaults to disabled when its configuration disappears; Core explicitly enables
it for floating workspaces. A manually loaded renderer can remain loaded after
configuration removal, unlike the config-owned lifetime exercised separately.

Core currently has no per-consumer button-list API. Familiar therefore uses a
small, explicitly tested **compatibility adapter**, not an advertised Core
extension API. Its existing `looknfeel.lua` include runs before Core's workspace
layout restoration. It wraps that module's one `apply()` call, temporarily
captures its two button declarations, then restores `add_button` immediately,
including on errors. Only after verifying those exact actions and Core's
workspace tag does it substitute three Familiar buttons and appearance settings.
Other Core behaviour runs unchanged. On a changed contract or unexpected load
order, the captured Core buttons are replayed unchanged and Familiar reports an
integration error. Repeated config reloads start fresh, never append another set.

Do not combine this with another theme/plugin that defines its own Hyprbars
buttons. Multiple registered backends are refused. A registration name alone is
not treated as library provenance; only Core requests the official library.
The package and Hyprland enforce their own exact ABI check.

## Migration, disable and rollback

Migration validates the exact owned include and installation identity, journals
its progress, replaces the old generated loader, and adds the include on a fresh
installation. It does not reload the compositor at that point. An old private
owner records `HYPRLAND_INSTANCE_SIGNATURE`; log out/in before applying the new
adapter. The same or unknown session cannot be treated as a retired private
mapping. Retry an interrupted migration with the same button. Previous native-only
handoffs require this explicit selection too.

After migration, style changes use the shared write/reload/verify transaction.
A failure restores the previous generated file without overwriting external
configuration edits. Stale instance teardown cannot remove a newer instance's
controls. Disable/removal reload Core defaults, never unload its library.
Missing package/Core support cannot resurrect Familiar's private loader.
Generated configuration checks the installed source's controls-v2 marker, so
rollback to an older source cannot keep invoking unsupported helper arguments.

Development installation retains the old binaries for rollback and still checks
source/artifact identity. Before replacing a helper on an official host, the
installer uses the verified bundle helper to restore Core defaults at the installed
path; it does not rely on asynchronous QML teardown or an older helper
understanding native button arguments. Official hosts allow only the audited v0.1.5 commit
`439f97480bb0803f32137dcb700fbb939dc959ff` or guarded newer source. Rolling back to
v0.1.5 restores that version's paused-controls behaviour, never private controls
over Core. No version, release pin, package channel or system package is changed.

## Validation and acceptance

Rust tests cover migration/session gates, transactional recovery, stale owners,
explicit targets and source guards. Lua tests execute the unmodified Core module
for Mac/Windows, tiled/floating workspaces, first load, changed Core, Core errors,
multiple backends and late includes. The desktop CI matrix adds the actual Core
revision and an unmodified official v0.2.1 renderer built against the guest's
Hyprland headers. Its dedicated test exercises real pointer buttons, minimise/
restore, reload, disable, removal and returning to tiling, and saves screenshots.
It also retains a manually loaded renderer while removing all titlebar
configuration, compares maximized client geometry against a no-renderer baseline,
then restores Core/Familiar configuration and clicks the restored minimise
button. Plugin identity and screenshots accompany those assertions; merely
unloading the library cannot satisfy the retained-renderer case.
This source-build test is not evidence of the published pacman artifact's delivery.

Record CI outcomes and exact artifact identity in the draft PR. Before merge,
Tom must accept that build on the XPS: migration/logout, the selected styles,
actual buttons and double-click/drag, theme changes, exclusions, mixed scaling,
disabling/removing Familiar and development rollback. Clipboard acceptance is
separate. Green CI is not XPS acceptance; #74 stays open until that acceptance.
