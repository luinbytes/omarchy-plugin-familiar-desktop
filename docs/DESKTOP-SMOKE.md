# Disposable desktop regression checks

`Desktop smoke` builds the exact PR head, then runs a real Hyprland compositor
and the pinned Omarchy Quattro shell in a disposable Arch VM on a GitHub-hosted
Ubuntu runner. KVM, a virtio GPU and Mesa software rendering provide the desktop.
The guest has its own systemd, login session and virtual display. Ephemeral SSH
keys are generated for each run; no personal desktop, repository secrets, host
display sockets or shared filesystems enter the guest.

The test fails if any prerequisite, desktop startup, assertion or timeout fails.
It never substitutes the QtTest mocks or treats an unavailable desktop as a pass.
It is an additional CI check; the existing portable tests remain independent.

## Scope

- Bootstrap a pinned v0.1.2 fixture using its real binary-download/setup helpers.
- Install the exact candidate with the production development installer.
- Require real shell and Familiar IPC responses.
- Register a disposable RSS Feed fixture, open its real shared-shell window,
  require the RSS glyph and plugin identity in Familiar, focus it, close it and
  verify cleanup. This covers catalogue integration, not RSS fetching or the
  physical Nerd Font glyph appearance on the XPS.
- Launch two real foot windows; verify their compositor identities.
- Activate, minimise and restore an exact window, checking actual compositor state
  and that minimising does not reveal the hidden workspace or hide the other window.
- Persist a Dock preference and use the actual Omarchy shell restart command.
  Require a changed shell PID, Familiar recovery, surviving windows and preference.
- Exercise window operations again after restart, require the real Dock layer,
  and capture a screenshot.
- Roll back with the production installer, checking the previous source identity,
  removal of the development receipt and live Familiar/window recovery.
- On the official-renderer case, also start the real shell with an enabled,
  unfinished v0.1.5 installation, stage with `--initial`, finish through the production
  setup entry point, and roll back active native controls to the prior unfinished
  source. Check placement, a later disabled state, Core defaults and the absence
  of any private library. The graphical wizard itself is not clicked.

The stable bootstrap is a test fixture, not a test of the graphical setup wizard.
This first smoke does not click Dock icons, inspect hover-preview pixels, trigger
notifications, test physical GPUs/displays/trackpads or measure performance.
Those remain explicit future extensions and XPS acceptance checks.

## Reproduction and evidence

The workflow pins the Arch cloud image (20261001.604814) with SHA-256, Arch snapshot date, stable Familiar
commit and Omarchy commit. Its artifact records installed package versions,
source SHA, upstream SHA, phase/exit code, logs, compositor state and screenshots.
The development artifact separately records source, run/attempt and binary hashes.
Third-party Actions version tags not already pinned by the repository remain a
separate supply-chain limitation; this is not a fully hermetic build.

The job has a 30-minute limit and individual readiness deadlines. Diagnostics
upload even on failure. Screenshots prove rendering occurred, not visual fidelity.
`session.sh` refuses to run outside the disposable CI account.

PRs trigger the workflow; manual dispatch becomes available after the workflow
reaches the default branch. The reusable build returns its exact artifact name,
so retrying only a failed desktop job uses the previously successful candidate
artifact, not a guessed new attempt. `tested-build.json` records the producing
attempt separately from the smoke workflow attempt.

Automated desktop success is not XPS hardware acceptance or authorization to
promote a branch to main or publish a version. See `WORKFLOW.md`.
