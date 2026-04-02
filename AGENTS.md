# AGENTS

## Purpose

This repository contains a macOS Swift client plus a Python RVC engine. Agent work in this repo must preserve the split between:

- `mac-client/`: SwiftPM-based macOS client
- `engine/`: Python engine and realtime/audio pipeline
- `scripts/`: packaging and shared workflow scripts

The default user-facing product is the packaged app built into `dist/SwiftRVCMacClient.app`.

## Repository Layout

- `mac-client/`
  - Swift Package executable target
  - UI, app state, bridge client, packaging resources
- `engine/`
  - FastAPI phase1 backend
  - realtime voice conversion controller
  - model/runtime lifecycle
  - nested git worktree status must be checked separately
- `scripts/build-macos-app.sh`
  - canonical app packaging entrypoint
- `scripts/release-check.sh`
  - canonical local release gate
- `scripts/app-info.sh`
  - packaged app metadata and artifact summary
- `scripts/bump-backend-api-version.py`
  - bumps backend API/build version and syncs the client compatibility constant
- `Makefile`
  - preferred shortcut entrypoints for common local tasks
- `docs/`
  - product and workflow documentation
- `dist/`
  - built `.app` artifacts, ignored by git

## Ground Rules

- Do not assume `engine/` changes will appear as normal file diffs from the root repository. Check both:
  - root: `git status --short`
  - engine: `git -C engine status --short`
- Treat realtime as opt-in. Default startup should not proactively initialize realtime device or route state unless the user explicitly requests it.
- Do not bind realtime audio devices during passive configure/status refresh.
- When changing lifecycle behavior, verify startup, stop, restart, and termination behavior together.
- Do not edit or revert unrelated user changes. At the time of writing, `docs/swift-rvc-mac-feature-overview.md` may already be user-modified.

## Standard Commands

### Preferred Entry Points

- Use `make help` first for the current local command index.
- Prefer these shortcuts over memorizing raw script paths:
  - `make bump-api-version`
  - `make dev-check`
  - `make release-check`
  - `make package`
  - `make app-info`
  - `make run-app`
  - `make swift-test`
  - `make engine-test`
  - `make status`
  - `make engine-status`
- Recommended daily command sequence:
  - inspect status: `make status && make engine-status`
  - run local gate: `make dev-check`
  - rebuild app when packaging matters: `make package`
  - inspect artifact: `make app-info`
  - launch packaged app: `make run-app`
  - run release gate before handoff: `make release-check`

### Swift Client

- Install/build test dependencies through SwiftPM:
  - `cd mac-client && swift test`
- Build release executable:
  - `make build-release`
  - this automatically bumps backend API/build version first
- Raw command:
  - `cd mac-client && swift build -c release`

### Python Engine

- Preferred interpreter:
  - `./engine/.venv/bin/python`
- Focused regression tests currently in place:
  - `./engine/.venv/bin/python -m unittest engine.tests.test_operation_state engine.tests.test_realtime_vc`

### App Packaging

- Canonical packaging command:
  - `make package`
  - or `bash scripts/build-macos-app.sh`
- Packaging automatically bumps backend API/build version and syncs the client compatibility constant.
- `make package` also prints the packaged app summary automatically.
- Raw script:
  - `bash scripts/build-macos-app.sh`
- Output:
  - `dist/SwiftRVCMacClient.app`
- Post-build metadata summary:
  - `make app-info`
  - or `bash scripts/app-info.sh`
- Launch the packaged app for manual verification:
  - `make run-app`

### Release Gate

- Canonical local release check:
  - `make release-check`
  - or `bash scripts/release-check.sh`
- Raw script:
  - `bash scripts/release-check.sh`
- This must validate:
  - shared tests
  - app rebuild
  - bundle structure
  - signature verification when available

### Standard Local Validation

- Run the shared validation script from repo root:
  - `make dev-check`
  - or `bash scripts/dev-check.sh`
- Raw script:
  - `bash scripts/dev-check.sh`

## Change Workflow

1. Read the affected Swift and Python boundaries before editing.
2. Make the smallest change that preserves the existing client/engine split.
3. Run targeted tests first.
4. Run `make dev-check` before claiming the repo is in a good state.
5. If packaging is relevant, rebuild the app with `make package`.
6. If you need to validate the packaged app locally, run `make run-app`.
7. For a release candidate, run `make release-check`.
8. Report:
   - files changed
   - tests run
   - whether packaging was rebuilt
   - whether release-check was run
   - any known gaps not validated manually

## Realtime-Specific Checklist

When touching realtime logic, verify all of the following:

- Default startup does not auto-start realtime.
- Realtime device state is only loaded on explicit user action.
- `LIVE` start/stop still works.
- Offline single convert and text-audio remain available when realtime is idle.
- Realtime and offline tasks stay mutually exclusive.
- Stopping realtime releases device bindings and does not leave stale route state.
- App termination performs best-effort runtime cleanup.

## Documentation Expectations

If a workflow or command changes, update at least one of:

- `AGENTS.md`
- `docs/development-workflow.md`
- `docs/release-workflow.md`
- `scripts/` helper entrypoints

Avoid adding process docs that are not backed by runnable commands in this repository.
