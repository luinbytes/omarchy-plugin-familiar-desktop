# Branch builds and desktop acceptance

Work on a feature branch with a draft PR. Green CI means ready for desktop
testing. Merge only after Tom accepts the exact build on the XPS and CI passes.
Changing the source invalidates acceptance for affected behaviour. Versions and
release tags are a separate, explicitly requested step. Do not create RC releases
for routine testing or treat a development artifact as a stable installer.

## Local checks

Install Rust 1.99 with rustfmt and clippy, Node 22 or newer, Lua 5.4, a C++20
compiler with Cairo development headers, and Qt 6 tools/modules. On Ubuntu the
Qt packages are `qt6-declarative-dev-tools`, `qml6-module-qttest`,
`qml6-module-qtquick`, `qml6-module-qtquick-window`,
`qml6-module-qtqml-workerscript`, `qml6-module-qtquick-controls`,
`qml6-module-qtquick-layouts` and `qml6-module-qtquick-templates`.

Run `tests/check` from the checkout. It checks Rust formatting and clippy,
runs Rust/Node and offscreen QML tests, renders the production settings view,
tests vector controls and parses plugin QML. `tests/run` remains the Rust/Node
subset. Override `QMLTESTRUNNER` and `QMLFORMAT` for tool paths outside
`/usr/lib/qt6/bin`. CI calls the same portable entry point, then builds binaries
and checks keyboard configuration on Lua 5.5.

See [ARCHITECTURE.md](ARCHITECTURE.md) for feature owners and testing boundaries.
A sandbox may block process visibility or Unix sockets; report those failures
and rely on the complete CI result instead of disabling those tests.

## Build when needed

Open Actions → Build for testing → Run workflow and select your feature branch.
The branch must contain the workflow and development installer support.
Alternatively:

```bash
gh workflow run dev-build.yml \
  --repo tcballard/omarchy-plugin-familiar-desktop \
  --ref feat/your-feature
gh run list --repo tcballard/omarchy-plugin-familiar-desktop \
  --workflow dev-build.yml --branch feat/your-feature
```

The workflow runs the portable suite, QML checks and binary builds. Only after
both reusable workflows succeed does it publish the x86_64
`familiar-dev-SHA-RUN-ATTEMPT` artifact, with matching static backend and Hyprbars
binaries. A native ARM runner also tests and builds a static backend and publishes
`familiar-dev-aarch64-SHA-RUN-ATTEMPT` after both portable architectures pass.
That ARM bundle is for Omarchy's official renderer and contains no private library.
Both bundles include an immutable source identity, installer, checksums and build
receipt. They create no release, tag or version change. Artifacts expire after
30 days: keep the downloaded bundle and your acceptance evidence. Rebuilds are
new evidence, even at the same SHA.

The PR path trigger also builds changes to the development/packaging pipeline.
Runtime changes require live acceptance; repository branch protection is managed
separately and is not changed by this workflow.

## Download and install on the XPS

Use the run ID printed by GitHub. Inspect its source SHA and confirm all jobs
passed. Download only a run from a branch you trust: its installer and binaries
are executable code. Checksums detect corruption; they do not make an untrusted
branch safe. GitHub authentication is required to download Actions artifacts.

```bash
repo=tcballard/omarchy-plugin-familiar-desktop
run_id=REPLACE_WITH_RUN_ID
artifact_name=REPLACE_WITH_FAMILIAR_DEV_ARTIFACT_NAME
gh run watch "$run_id" --repo "$repo" --exit-status
test_dir="$(mktemp -d "$HOME/familiar-dev.XXXXXXXX")"
gh run download "$run_id" --repo "$repo" \
  --name "$artifact_name" --dir "$test_dir"
cd "$test_dir"
sha256sum --check --strict SHA256SUMS
cat DEV-BUILD.json
bash install-dev.sh
```

Requires an existing, working Familiar installation on the supported Linux
x86_64 / Hyprland ABI, with git, jq and the usual Omarchy tools. On hosts with
Omarchy’s official titlebar package, Core owns ABI compatibility: the installer
skips private titlebar setup and supports only guarded source/rollback targets
(see [migration details](TITLEBAR-MIGRATION.md)). Select **Use Familiar controls**
in Familiar after installation; migration from a private backend needs logout/login. No compiler is
needed. Local source changes and unexpected ignored files stop installation.
Older installations without `setup-in-app.sh` are supported when their binaries
match the checksum pins in their installed commit and titlebar ownership matches.
Missing pins or corrupt binaries stop for repair before disabling the plugin.
The installer disables Familiar and restarts the shell before changing source or
binaries, including initial staging and rollback. After staging succeeds it restores
Familiar's placement and previous activation state and restarts the shell again.
A previously disabled plugin stays disabled. It retains pins, dock settings and
the saved mac/windows titlebar style; unrelated shell configuration is preserved.

Stable release checksums stay unchanged. A local receipt binds development
binary hashes to the installed source SHA and directory. Setup accepts it only
for a clean matching checkout. In-app release repair is unavailable during dev
testing; use this installer to update or roll back. Do not run the normal plugin
updater during a development test; moving the source invalidates its receipt.

## ARM CI builds with official titlebars

On a Linux aarch64 desktop with Omarchy's official titlebar package installed,
download the `familiar-dev-aarch64-SHA-RUN-ATTEMPT` artifact from a successful
development or desktop-smoke workflow. This is an installable development bundle,
not the raw GNU test binary uploaded by the portable checks. It uses the static
`aarch64-unknown-linux-musl` backend, built and tested on a native ARM runner;
no compiler is needed on your desktop. Core provides the renderer and its ABI.

Use the download command above with this ARM artifact's exact name and producing
run. From the downloaded directory:

```bash
sha256sum --check --strict SHA256SUMS
cat DEV-BUILD.json
bash install-dev.sh --initial
```

Use `--initial` only for an unfinished, registered Familiar source checkout. For
an existing working development installation, omit `--initial`. Initial staging
preserves activation and placement; open Familiar (enable it if it was previously
disabled) and finish setup, then choose **Use Familiar controls**. Keep the bundle
and printed snapshot; rollback is `bash install-dev.sh --rollback`.

This bundle refuses private-renderer hosts before disabling or changing Familiar.
Those hosts still need the local build below to match their installed Hyprland ABI.
An ARM CI pass does not establish ARM desktop acceptance: record the actual
desktop environment, receipt, scenarios and results for the exact artifact.

## Native ARM development on the target desktop

The stable v0.1.5 release publishes x86_64 assets only. Adding ARM support to
source does not publish ARM assets or authorize a release. The standalone stable
recovery installer and release build/tag pipeline remain x86_64. ARM users can
test the official-renderer CI bundle above or an explicit local development
bundle; the setup UI never compiles or installs system packages. Portable CI
checks both x86_64 and aarch64.

On the target Linux aarch64 desktop, use Rust, Node, Git and readelf. When Omarchy's
official titlebar package is installed, the local builder produces only Familiar's
backend: no private renderer, compiler for Hyprland plugins or Hyprland headers are
needed. On older private-renderer hosts, also install make, a C++ compiler,
pkg-config, Glaze and the installed Hyprland development headers/dependencies.
Commit the feature branch before building. From that clean checkout, run:

```bash
bash scripts/build-local-dev.sh "$HOME/familiar-arm-build"
cat "$HOME/familiar-arm-build/DEV-BUILD.json"
FAMILIAR_SOURCE_REPOSITORY="$PWD" \
  bash "$HOME/familiar-arm-build/install-dev.sh" --initial
```

The native backend uses the target desktop's GNU toolchain and shared-library
environment; this is not a portable static release binary. Cargo's output directory
and native target are explicitly controlled, so environment/configuration overrides
cannot cause a stale default-path binary to enter the bundle. Private Hyprbars uses the
same pinned upstream commit and vector-controls patch as release builds. Its
build probes the real installed headers and refuses a header ABI different from
the running compositor. The bundle contains one architecture/ABI pair, or just the
architecture-matched backend with `renderer: omarchy`. Core owns the official
renderer and its ABI. Bundles carry SHA-256 checksums and a receipt bound to the exact
source commit. Local receipts say `buildKind: local` with a build timestamp;
they never invent a GitHub run or XPS acceptance record. Keep the bundle and its
build evidence for review. The explicit source repository override permits a
local checkout or contributor fork; the fetched commit must still match exactly.

`--initial` is only for an installed Git plugin with no native binaries or active
titlebar hook, including setup that previously stopped at the x86_64 check.
Private/foreign ownership is refused. A hook-free Core delegation receipt for this
installation is preserved and permits retry after official-host initial rollback.
It preserves personal preferences, snapshots the unfinished setup and stages
verified native binaries. Open Familiar (enable it first if it was previously
disabled) and start setup. On a private-renderer host choose Mac or Windows controls;
on an official host finish setup, then choose **Use Familiar controls** in Window
controls. Existing private owners still need the explicit migration and logout/login.
Setup verifies source and bytes again and performs its normal guarded
configuration transaction without release downloads. Retry uses those same
verified development bytes. Once ready, development repair remains through the
bundle installer. For later development updates use `install-dev.sh` without
`--initial`, then test the new exact build again.

Rollback uses `bash "$HOME/familiar-arm-build/install-dev.sh" --rollback` (or
the explicit snapshot path printed at install). An initial rollback removes the
owned hook through the verified helper, restores the previous source and pending
markers, and removes staged binaries/receipt; personal settings remain. An
interrupted stage without a receipt can be rolled back only when no hook was
activated; partial files are removed without being executed. Completed installations
must still match their receipt. Failures after disabling leave Familiar inactive
until rollback/recovery. The snapshot retains the previous activation and placement.
Official snapshots require the official package to remain installed, and rollback
clears native actions with the verified new helper before installing an older one.

Test setup/retry, both control styles, dock/window actions, config errors and
rollback on the ARM desktop. This evidence complements the required maintainer
XPS acceptance and merge authorization in [WORKFLOW.md](WORKFLOW.md); it does not
replace them. Stable ARM publication still needs a separately authorized binary
build/release path and reviewed source-bound pins for each supported ABI.

## Roll back

Keep the bundle directory. From it:

```bash
bash install-dev.sh --rollback
```

The installer prints an explicit snapshot path for each installation; pass it
after `--rollback` to select that point. A snapshot retains the previous commit,
the replaced binaries and any previous development receipt. Official-host installation
does not replace any private library; it retains those bytes in place. Rollback
verifies those bytes and restores them together, including after a failed setup.
User preferences are not reverted wholesale. Snapshots remain under
`~/.local/state/familiar-desktop/dev-snapshots` (or `$XDG_STATE_HOME`).
Failures stop before enablement where possible and print recovery instructions.
Do not delete a snapshot while you still need its rollback point.

## Record acceptance in the PR

- Commit SHA, CI run URL and attempt; artifact name/digest from GitHub.
- XPS / Omarchy / Hyprland versions and monitor scaling.
- Scenarios exercised, result and remaining limitations.
- Explicit accept/reject decision for that build.

For hover previews and widget placement, use `docs/DOCK-PREVIEWS.md`.
For this installer, exercise stable → dev, dev → dev, failed setup recovery and
dev → previous install. Mock desktop tests do not establish live shell behaviour.
