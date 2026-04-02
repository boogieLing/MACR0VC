# Release Workflow

## Scope

This document defines the current local release workflow for `RVC-WebUI-MacOS`. It is intended for local packaging validation before a handoff, not for notarization or external distribution.

## 1. Preconditions

Before running the release flow:

1. Check root repository status:
   ```bash
   git status --short
   ```
2. Check nested engine status:
   ```bash
   git -C engine status --short
   ```
3. Confirm no unrelated local changes are being accidentally bundled.

## 2. Standard Release Gate

Run:

```bash
make release-check
```

This does all of the following:

1. Runs `bash scripts/dev-check.sh`
2. Rebuilds `dist/SwiftRVCMacClient.app`
3. Automatically bumps backend API/build version during packaging
4. Verifies bundle structure
5. Verifies critical `Info.plist` fields
6. Runs `codesign --verify --deep --strict` when `codesign` is available
7. Prints a compact app bundle summary

## 3. Output

Expected app path:

- `dist/SwiftRVCMacClient.app`

Optional standalone artifact summary:

```bash
make app-info
```

To launch the packaged app from `dist/` for a manual smoke check:

```bash
make run-app
```

Expected required bundle contents:

- `dist/SwiftRVCMacClient.app/Contents/Info.plist`
- `dist/SwiftRVCMacClient.app/Contents/MacOS/SwiftRVCMacClient`
- `dist/SwiftRVCMacClient.app/Contents/Resources/AppIcon.icns`

## 4. Handoff Checklist

Before considering a local release candidate ready:

1. `make release-check` passed
2. The `.app` launches locally
   Recommended command: `make run-app`
3. Core offline workflows still work:
   - single convert
   - text-to-audio generation
4. If realtime-related code changed, manually verify:
   - startup does not auto-initialize realtime
   - explicit realtime initialization still works
   - stopping realtime releases device bindings

## 5. Known Limits

This repository currently does not automate:

- notarization
- Developer ID signing
- DMG creation
- release notes generation

If those become part of the standard workflow, extend the scripts first, then update this document.
