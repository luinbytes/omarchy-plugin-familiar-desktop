# Code map and ownership

Read [WORKFLOW.md](WORKFLOW.md) first. Start each maintenance change on a feature
branch. Run `tests/check` before preparing a source-bound development build.

## Where to make a change

| Behaviour | Owner and entry point | Focused coverage |
| --- | --- | --- |
| Durable dock and titlebar preferences | `components/SettingsStore.qml`, `components/SettingsSchema.js`; service aliases in `DockPanel.qml` | `tst_SettingsStore.qml`, `test_widget_config.cjs`, `test_dock_opacity.cjs` |
| Settings navigation and controls | `components/SettingsContent.qml`, `SettingsFrame.qml`, `PreferenceToggle.qml`, `PreferenceSection.qml`; `BarWidget.qml` opens the modal and reads the service | `test_settings_layout.cjs`, `tst_SettingsFrame.qml`, `tst_PreferenceToggle.qml`, `tst_PreferenceSection.qml` |
| Dock lifecycle, monitors and visibility | `DockPanel.qml` wires `components/DockVisibility.qml`; policy in `DockSettings.js`, placement in `DockGeometry.js` | `tst_DockVisibility.qml`, `test_dock_position.cjs`, `tst_DockSettings.qml`, desktop smoke |
| Window observations and focus history | `components/DockWindowTracker.qml` owns live-window ordering, focus requests and terminal title settling | `tst_DockWindowTracker.qml`, `test_window_history.cjs`, desktop smoke |
| Dock appearance observations | `components/DockAppearance.qml` owns compositor border/rounding/animation queries and background alpha | `tst_DockAppearance.qml`, desktop smoke |
| App matching and window history | `DockModel.js` facade → `DockMatcher.js`; normalized lookup in `DesktopCatalog.js`, curated data in `AppCatalog.js` | `test_desktop_catalog.cjs`, `tst_DockMatcher.qml`, `test_window_history.cjs`, `test_app_identity.cjs` |
| Popup selection and editing | `components/DockInteraction.qml`; `FolderIconPicker.qml` takes data and emits actions | `tst_DockInteraction.qml`, `tst_FolderIconPicker.qml` |
| Drag ordering and cancellation | `DockDrag.js` supplies shared slot/drop calculations; `components/DockDragState.qml` owns dock/folder drag state | `test_dock_drag.cjs`, `tst_DockDragState.qml` |
| App tile activation and window selection | `components/AppTileInteraction.qml` is used by `DockItem.qml` and `components/FolderPopup.qml` | `tst_AppTileInteraction.qml`, `test_dock_scroll.cjs`, desktop smoke |
| Notification and title badge grouping | `AppIdentity.js`, `components/NotificationTracker.qml` | `tst_NotificationTracker.qml` |
| Runtime icon sources and shell-panel identity | `IconResolver.js`, `PluginPanels.js`, `components/AppIcon.qml`; registered widget names and existing widget glyphs feed `DockModel.js` | `test_app_identity.cjs`, `test_desktop_catalog.cjs`, `tst_DockWidgetSlot.qml`, desktop smoke |
| Pins, folders and launching | `DockPinned.js`, `DockAutoName.js`, `DockLauncher.js`; menu/popup QML | Node model checks, desktop smoke |
| Left/right hosted widgets | `components/DockWidgetSlot.qml`, `HostedWidgets.js`, `DockWidgets.js`; service action adapter | `test_widget_anchor.cjs`, `tst_DockWidgetSlot.qml` |
| Ordinary preference requests | `components/BackendRequest.qml`; small Caps Lock, Gestures, InputPreference, WindowMode and Taskbar controllers | Corresponding QtTest controller tests |
| Native configuration changes | Feature modules in `backend/src`; shared `config_file::apply_generated` transaction | `backend/tests/config_file.rs`, `backend/tests/config_transactions.rs` and feature integration tests |
| Titlebar reconciliation | `components/TitlebarController.qml`, `backend/src/titlebars.rs`, `hyprbars/` | Titlebar backend/QtTest tests; exact-build desktop acceptance |
| Setup, downloads and repair | `components/SetupController.qml`, `setup-in-app.sh`, installer scripts | Setup QtTest, installer Node fixtures |
| Taskbar shell-layout snapshot | `backend/src/taskbar.rs`, `components/TaskbarApps.qml` | Taskbar backend/QtTest tests and bar placement fixtures |
| Development/release packaging | `scripts/prepare-dev-bundle.cjs`, `scripts/install-dev.sh`, workflows | Development/release packaging and rollback fixtures |

Paths in this table are relative to the repository (tests are under `tests/`
unless a backend path is given). Follow the facade for model callers; importing a
private matching implementation into a view creates a second API to maintain.

## State boundaries

`DockPanel.qml` is the hosted service and the only runtime owner of
`~/.config/omarchy/familiar-desktop-settings.json`. Its SettingsStore watches the
file, validates known fields and preserves unknown fields. Views bind to service
properties and call service setters; they must not read or write a second copy.
Malformed external settings are preserved and surfaced as an error.

Pins have a separate `familiar-desktop-pinned.json` file. Window focus history,
hover/drag state, widget instances and icon lookup caches are session state.
DockInteraction owns the single popup selection and editor state. Service
properties such as `activeStackItem`, `contextApp` and `isEditMode` are read-only
views. Call interaction methods to open, dismiss or edit; do not assign those
properties. Selection uses an ID resolved against current dock items, so model
refreshes and reordering update open popups and removed items dismiss them.
FolderIconPicker emits icon/dissolve requests; its window receives placement,
appearance and interaction inputs rather than the entire service.
DockDragState owns the drag indices. Dock and folder delegates request start,
hover and cancellation through `service.drag`; exposed service indices are
read-only. DockDrag computes neighbour slots and the same rail target for hover
feedback and drop, including merge intent and outer-edge insertion.
AppTileInteraction owns each app tile's window preview index, smooth wheel
accumulation and expiry. Dock and folder views route its launch/restore requests
to the service, and keep their own visuals, edit actions and rail/grid dragging.
Launch callers supply the current known windows explicitly for CLI hints.
DockVisibility receives monitor/window providers, availability and surface hover
inputs. It owns reveal overrides, target monitor, inactivity timers and the widget
picker's temporary reveal; it requests popup closure by signal. DockWindowTracker
receives the window providers and emits refresh, icon-refresh and validated focus
requests. DockAppearance observes compositor/theme appearance and supplies the
rendering properties. The service exposes read-only views of their state, rather
than keeping additional copies. Dormant keyboard-capture state is not retained:
the current policy shows all outputs or the configured workspace's output.

The matcher library's disk icons and CLI hints are updated by the service and
shared through `DockModel`; settings views do not mutate them. Notification event
counts and urgency persist, while title-derived unread counts are a live snapshot.
Private notification text never belongs in a command argument.

`AppIdentity.toCanonical` creates a grouping/badge key, not a launch identifier.
Keep exact desktop/PWA IDs for launching and pins. `AppCatalog` contains static
metadata; changes to an alias should have a grouping regression test. Icon lookup
uses the same candidate priority everywhere, with an explicit friendly fallback
for app tiles and a generic fallback for previews.

DesktopCatalog normalizes installed entries once per dock rebuild and applies
one ordered lookup for both indexed and ordinary callers. App identity keys
outrank shared icon aliases, and web-app URLs outrank browser launch commands.
DockMatcher prepares each window once and builds the same app item shape for
pinned, running and folder apps. Original entries, launch commands and window
objects remain the source of actions; normalized metadata only assists matching.
Registered panel names distinguish shared `org.quickshell` windows by exact title;
ambiguous titles retain the generic shell identity. Panels keep their real window
objects, but pins use plugin IDs and reopen through the same public shell command
as Familiar's widget slots (its own scoped service facade cannot control other plugins).
AppIcon renders widget glyphs with the shell font in dock/taskbar, folder grids and
folder popups; image icons continue through the normal theme lookup. RSS Feed uses
the same U+F09E glyph as its bar widget. Plugin names alone never reclassify ordinary
Qt apps. The catalogue covers enabled bar-widget plugins; unregistered panels and
panels with a different window title keep the existing fallback.
DockGeometry supplies edge anchors, exclusion-aware popup margins, surface sizes
and app-menu clamping for the dock and popup windows.

## Backend boundaries

QML requests an explicit operation; Rust owns native configuration edits.
Ordinary controllers declare allowed choices, expected response modes and
arguments on BackendRequest. Invalid input, overlapping requests and malformed
responses fail without optimistic success. Setup's streaming output and the
revision/ownership lifecycle of titlebar reconciliation remain specialized.

Each native preference module validates its owned hook, migration and generated
Lua, and takes its feature lock. It supplies expected/new bytes to
`config_file::apply_generated`, which writes the owned generated file, replaces
the main config with a backup, reloads, checks configuration errors and runs any
feature verification. Failure restores the previous bytes only if they still
match; external edits stop rollback. Reset removes the owned file after a
successful reload. Taskbar and titlebar transactions retain their distinct
ownership and restoration rules.

## Validation and extension

Use `tests/check` as the portable entry point. Qt tests use inert Quickshell
imports; they do not prove compositor behaviour. Installer fixtures use temporary
homes and fake desktops. Add behaviour tests at exported JS functions or component
APIs; avoid extracting functions using nearby comments or layout text.

For a preference: extend SettingsSchema/SettingsStore, bind a PreferenceToggle
or the appropriate control to the service setter, and test restore/save/defaults.
The toggle emits a requested value; it never mutates or breaks the owner binding.
Controller-backed choice panels use PreferenceSection: each feature supplies
its choices and copy, while the component reads selection/status and requests
the controller's existing operations. Rendering never applies a preference.
For a native operation: keep parsing
and Lua in its feature module and use the shared transaction. For a hosted widget:
use DockWidgetSlot on both sides and supply the narrow action adapter.

A passing portable suite is readiness for desktop testing. Follow
[DEVELOPMENT.md](DEVELOPMENT.md), [DESKTOP-SMOKE.md](DESKTOP-SMOKE.md) and
[DOCK-PREVIEWS.md](DOCK-PREVIEWS.md) for source-bound builds, real lifecycle checks
and rollback. The official titlebar adapter has its compatibility contract and acceptance gates
in [TITLEBAR-MIGRATION.md](TITLEBAR-MIGRATION.md).
