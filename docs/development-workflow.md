# Development Workflow

## Scope

This document defines the current standard development flow for `RVC-WebUI-MacOS`. It is intentionally minimal and only documents commands that are already available in this repository.

## 1. Working Areas

- `mac-client/` is the Swift macOS client.
- `engine/` is the Python backend and realtime/audio runtime.
- `dist/` is generated output and must not be edited manually.

## 2. Before You Change Code

1. Check root repo status:
   ```bash
   git status --short
   ```
2. Check nested engine status:
   ```bash
   git -C engine status --short
   ```
3. Read the relevant boundary files before editing.

## 3. Development Rules

- Default startup should keep realtime uninitialized until the user explicitly interacts with realtime features.
- Offline single convert and text-audio generation are the default available workflows.
- Realtime, single convert, batch convert, and text-audio must remain mutually exclusive when they share foreground engine ownership.
- Cleanup work must consider:
  - launch cleanup
  - stop/restart cleanup
  - app termination cleanup
  - stale port/device/runtime state

## 4. Standard Validation

Run the shared validation script:

```bash
make dev-check
```

This currently runs:

- `swift test`
- `./engine/.venv/bin/python -m unittest engine.tests.test_operation_state engine.tests.test_realtime_vc`

If you prefer the raw script, it is still:

```bash
bash scripts/dev-check.sh
```

If you change only one side of the repo, you may run targeted checks first, but the shared validation script is the standard final gate.

## 5. Version Bump Rule

Every release build must update the backend API version and keep the Swift client compatibility constant in sync.

Manual entrypoint:

```bash
make bump-api-version
```

This is also run automatically by:

- `make build-release`
- `make package`

## 6. Build Artifacts

### Release Executable

```bash
make build-release
```

### Packaged App

The standard app build is:

```bash
make package
```

This command now also prints the packaged app summary automatically.

Expected output:

- `dist/SwiftRVCMacClient.app`

To reprint the compact bundle summary without rebuilding:

```bash
make app-info
```

To launch the packaged app for local verification:

```bash
make run-app
```

## 7. Release Validation

For a release candidate, run:

```bash
make release-check
```

This is the standard local release gate and should be preferred over manually chaining test and packaging commands.

## 8. Delivery Checklist

Before handing work back:

1. Confirm changed files.
2. Confirm tests run.
3. Confirm whether `dist/SwiftRVCMacClient.app` was rebuilt.
4. Confirm whether `make release-check` was run for release-facing work.
5. Call out any manual validation still missing.

## 9. Current Gaps

This workflow is now documented, but it is still intentionally lightweight. The next useful additions would be:

- broader Python backend regression coverage
- packaging verification checks
- a documented release checklist for signing and distribution
