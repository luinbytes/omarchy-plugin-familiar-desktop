# Contributor fixes for v0.1.6

Reviewed 12 October 2026. This is an integration candidate, not desktop
acceptance or merge approval. Follow [WORKFLOW.md](WORKFLOW.md).

## Source and scope

- Stable main: `439f97480bb0803f32137dcb700fbb939dc959ff` (v0.1.5).
- PR #84: `b617aca2fd2af99341241ca6836ff4e1065b8b53`, including titlebars v0.2.1.
- PR #86: `54156405e304fffa901619e37c2b9d36abccf690`, including ARM builds and
  guarded setup/rollback. Both histories are retained in the integration branch.
- PR #89: `cfd47271c2da080c7829f94ebfef5d511d113601`.
- PR #90: `46ebe315f04011edf1741888e4c09c14f9db3e47`.
- PR #91: `dcdc42bbd9c130012becbd953e90550d76f59194`.

Branch: `integration/v0.1.6-contributor-fixes`. The candidate keeps the existing
Mac and Windows modes. The dock-focused transition remains after v0.1.6 under
[issue #87](https://github.com/tcballard/omarchy-plugin-familiar-desktop/issues/87).
Product version and stable binary pins are unchanged.

## Decisions

| Contribution | v0.1.6 decision | Reason and integration |
| --- | --- | --- |
| #89: isolate installer XDG directories | Include | Fixtures must not read or modify the developer's desktop. Keep the explicit shell layout fixture. |
| #89: restore Show Desktop before updates | Include | All released 0.1.x helpers have the operation. The old 0.1.0-only condition strands parked windows. Keep the 0.0.x exception and positive event-presence assertions. |
| #89: remove stale development receipt | Include | Remove it only after successful plugin removal; failed uninstall retains it, and recovery snapshots survive. This prevents a later stable install being misclassified as an invalid development build. |
| #89: physical paths in repair/setup | Include | Match the backend's canonical source identity through a symlinked home. Resolve the test conflict by running the symlink case before development/official-host cases; retain all ARM, source-receipt and official-host coverage. |
| #89: refuse any official titlebar package | Adapt, do not take the guard unchanged | Correct for the old private-only standalone installer, but unsuitable as the v0.1.6 renderer policy. Standalone install and repair were still private-only even though in-app/development setup supported Core. They now skip private ABI/download/setup on official hosts and retain explicit controls migration in the UI. |
| #90: whole-line hook markers | Include | Caps Lock must not claim the Command or resize namespace. Exact hook-byte validation still rejects recognised edited/foreign hooks; shared configuration transaction tests remain required. |
| #90: full PWA profile suffix | Include | Profile 1 must not focus Profile 10 or suppress its own launch fallback. Independent of titlebar work. |
| #91: drag cleanup during destruction | Include | A destroyed MouseArea can leave the service drag index active. Emit cancellation from the owning tile's destruction; do not perform a drop or reorder. QtTest covers the real tile and shared drag state, not the full compositor. |
| #91: per-window CLI scan protocol | Defer from this candidate | The direction is useful, but the new regression is not in `tests/run`, and evidence can remain stale or ambiguous as detailed below. Keep this change separate from the release fixes. |

Fred Nix (`nixfred`) authored the seven selected commits. Local cherry-picks
retain his author metadata and original SHA trailers; connector-published
commits retain the source SHA trailers and credit him with `Co-authored-by`
because this environment has no authenticated Git push. The standalone/repair
adaptation also credits his official-package fixture. Kirill Kostin's ARM
authorship remains in #86's preserved history. No original PR is closed or
represented as fully merged by this integration.

## CLI attribution findings in #91

`tests/test_cli_attribution.cjs` is new, but `tests/run` never invokes it. The
canonical portable check therefore misses those new assertions.

A temporary probe against the exact PR head, using its real `DockMatcher.js`
and the existing JS loader, kept the same terminal object and generic title:

1. Publish `{address: "0x1", app: "btop"}`: the window groups under btop.
2. Publish `{address: "0x1", app: "yazi"}`: it still groups under btop.
3. Publish an empty scan: it still groups under btop.

The sticky cache runs before fresh scanner evidence. The PR stops a global
result infecting every unrelated terminal, but does not solve stale process
attribution within a window. This is an existing class of bug that its claimed
per-window evidence does not fully address; it is not presented as a new
regression caused by the PR.

Source inspection also shows `scan_cli_apps` calling `extract_cli(title, pid)`
for each client. That routine walks the PID's descendants before considering
the title. Two client windows reporting one terminal process therefore inspect
the same process tree and can acquire the same app label. This is a code-level
ambiguity, not a reproduced live-terminal result. Address-tagging that answer
does not establish which window owns the child process.

Before taking this part, wire the regression into the canonical runner; define
fresh/empty scan invalidation versus title marquee persistence; and test shared
terminal PIDs, app exit/replacement, and launch hints. Then deliver matching QML
and backend bytes and test a real multi-window terminal. #90's PWA hunk and
#91's CLI hunk are separate regions of `backend/src/dock.rs`; their filename
overlap is not by itself a conflict. The new backend tests must both survive any
later combined integration.

## Workflow review and evidence

The three source diffs were inspected before executing selected code. They
contain no workflow, dependency, lockfile, publishing or permission changes.
Their PR workflows use GitHub-hosted runners and read-only repository contents;
the release upload job is gated to a published release event. No contributor
workflow was approved or rerun during this review: the available connector has
no workflow-approval operation. `action_required` is not passing CI.

Original run IDs at review:

| PR | Portable | Binary build | Desktop smoke | Development build |
| --- | --- | --- | --- | --- |
| #89 | 38193206832 | 38193206903 | 38193207061 | 38193206858 |
| #90 | 38193208169 | 38193208430 | 38193208534 | No separate run returned |
| #91 | 38193209944 | 38193210203 | 38193210349 | No separate run returned |

All returned runs concluded `action_required`. New automated evidence must be
recorded on the integration draft PR against its exact source SHA, run and
attempt. Passing historical #84/#86 runs cannot certify this combined source.

Local shell syntax/diff hygiene and the installer, source-identity, uninstall,
repair and both architecture-parameterised in-app setup fixtures passed. Rust
formatting and Clippy passed. After building the workflow-pinned Lua 5.5.0, all
99 focused Rust tests passed across `caps_lock`, `config_file`,
`config_transactions`, `dock`, `input_preferences` and `titlebars`. The full
Rust suite stopped at the unchanged `force_quit` process-visibility test with
`Application has exited`, consistent with the earlier branch's documented host
limitation. Qt dependencies could not be installed in this host. Qt/compositor
and ARM execution are not established by the local x86_64 fixtures. No passing
full suite is inferred; the current CI result remains required.

## Acceptance still required

Keep the existing #84/#86 XPS checklist: actual packaged official-renderer
migration/logout, Mac/Windows buttons, theme/exclusions, drag/double-click,
scaling/monitors, disable/removal, initial setup and source-bound rollback;
also Qt 6.12 clipboard owner/IME/focus cases. Record ARM desktop evidence
separately from ARM CI and keep support claims within that evidence.

Add the following affected scenarios for the final matching development build:

- Command and resize hooks with Caps Lock in both enable orders; change/reset
  and uninstall while preserving unrelated configuration.
- Uninstall a development build, then clean stable installation/setup; failed
  uninstall keeps its receipt and all recovery snapshots.
- Show Desktop followed by update from an affected 0.1.x version; windows return.
- Setup/repair through a symlinked home, including official-renderer hosts.
- Standalone install/update/repair on official hosts, package unchanged, no
  private download and controls migration still explicit. Private hosts retain
  the ABI refusal and corruption/failure paths. The standalone stable installer
  still claims x86_64 only; ARM stable-release packaging is not added here.
- PWA Profile 1 and Profile 10 concurrently, then only Profile 10 open; target
  focus and launch fallback select Profile 1 correctly.
- Destroy/rebuild a dragging dock tile through window/badge refresh; drag state,
  cursor, previews and autohide recover, with no unintended reorder.

CI green means ready for desktop testing. Tom must accept the exact final build
and authorize merge; release publication remains separate. Main stays stable.
