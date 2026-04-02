# MACR0VC

MACR0VC is a macOS-first RVC workstation that combines a Swift desktop client with an integrated Python voice engine for single-file conversion, batch jobs, realtime voice conversion, text-to-audio voice matching, UVR separation, task tracking, and result archiving.

**English** | [简体中文](./docs/README.zh-CN.md)

<p>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-d97706?style=flat-square" alt="PolyForm Noncommercial 1.0.0" /></a>
  <a href="https://github.com/boogieLing/MACR0VC"><img src="https://img.shields.io/github/stars/boogieLing/MACR0VC?style=flat-square" alt="GitHub Stars" /></a>
  <a href="https://github.com/boogieLing/MACR0VC/forks"><img src="https://img.shields.io/github/forks/boogieLing/MACR0VC?style=flat-square" alt="GitHub Forks" /></a>
  <img src="https://img.shields.io/badge/Swift-6.2-f97316?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.2" />
  <img src="https://img.shields.io/badge/macOS-14%2B-111827?style=flat-square&logo=apple&logoColor=white" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Python-Backend-3776AB?style=flat-square&logo=python&logoColor=white" alt="Python Backend" />
  <img src="https://img.shields.io/badge/FastAPI-Integrated-009688?style=flat-square&logo=fastapi&logoColor=white" alt="FastAPI Integrated" />
</p>

![MACR0VC showcase](./docs/assets/readme/showcase.png)

---

[What MACR0VC Is](#what-macr0vc-is) ·
[Core Capabilities](#core-capabilities) ·
[Screenshots](#screenshots) ·
[Quick Start](#quick-start) ·
[Common Commands](#common-commands) ·
[Architecture](#architecture--repository-layout) ·
[Workflow Highlights](#workflow-highlights) ·
[Contribution](#contribution) ·
[License](#license--usage-restrictions) ·
[Star History](#star-history)

## What MACR0VC Is

MACR0VC is built for creators and voice workflow operators who want one local macOS interface for the full RVC loop instead of stitching together separate scripts and tools.

The project combines:

- A Swift macOS desktop client in `mac-client/`
- A Python/FastAPI voice engine in `engine/`
- A packaging and release flow centered on `dist/SwiftRVCMacClient.app`

The app is designed around real production-facing flows rather than isolated demos:

- load a source file and convert it into a target voice
- queue batch conversions
- run realtime voice conversion when explicitly enabled
- generate source speech from text, then convert it into the selected target voice
- separate vocals and instrumental stems with UVR
- monitor active work in `TASK`
- revisit outputs and linked artifacts in `RES`

## Core Capabilities

### Voice conversion workflows

- Single-file voice conversion with shared patch controls
- Batch conversion for queued directories or file sets
- Realtime voice conversion with explicit route selection and lifecycle feedback
- Text-to-audio generation routed into the active RVC target voice

### Production support tools

- UVR vocal / instrumental separation for source preparation
- `TASK` queue visibility for active work, status, and run windows
- `RES` archive with historical outputs, linked source artifacts, and cleanup actions
- Background merge and playback tools for output review

### Local packaging and validation

- Release app packaging into `dist/SwiftRVCMacClient.app`
- Shared `make` entrypoints for development checks and release verification
- Explicit command surface for app summary, launch, and release gate validation

## Screenshots

### Main Workspace

The main workspace brings patch selection, realtime controls, offline conversion controls, playback, and runtime indicators into one screen.

![MACR0VC main workspace](./docs/assets/readme/main-workspace.png)

### Input Center

The input panel supports direct audio loading as well as text-driven speech generation into the current target voice.

![MACR0VC input center](./docs/assets/readme/input-center.png)

### Completed Conversion View

Completed conversion results remain immediately playable, reviewable, and merge-ready from the main workspace.

![MACR0VC completed conversion](./docs/assets/readme/completed-conversion.png)

### RES Archive

The archive keeps historical outputs, source links, model context, and cleanup actions in one place.

![MACR0VC result archive](./docs/assets/readme/res-archive.png)

### TASK Queue

The task queue surfaces the active job, run progress, current input, and recent status transitions.

![MACR0VC task queue](./docs/assets/readme/task-queue.png)

## Quick Start

### Prerequisites

- macOS 14 or later
- Swift toolchain compatible with `swift-tools-version: 6.2`
- A local Python environment for the integrated backend under `engine/`
- At least one RVC voice model checkpoint available for inference

### 1. Clone the repository

```bash
git clone git@github.com:boogieLing/MACR0VC.git
cd MACR0VC
git submodule update --init --recursive
```

`engine/` is tracked as a submodule. If you skip submodule initialization, the backend code, bundled assets, and any sample model snapshot inside the engine repository may be missing locally.

### 2. Prepare models and inference assets

MACR0VC will not be usable until both the voice model files and the base inference assets are available.

Required model locations:

- `engine/assets/weights/`
  should contain at least one `.pth` voice model checkpoint
- `engine/assets/indices/`
  can contain matching `.index` files for the selected voice model

Required base inference assets:

- `engine/assets/hubert/hubert_base.pt`
- `engine/assets/rmvpe/rmvpe.pt`
- `engine/assets/rmvpe/rmvpe.onnx`

Current repository snapshots may already include sample weights and indices. If your local clone does not include them, add your own `.pth` and optional `.index` files before expecting single, batch, realtime, or text-driven conversion to work.

Model selection rules:

- `VOICE MODEL` will stay on `Choose target voice` until at least one valid `.pth` file is visible to the backend
- `.index` files are optional, but they improve similarity for many voices
- the client tries to auto-match an index whose filename resembles the selected model name
- `SPEAKER ID` matters only for multi-speaker models; single-speaker models should stay on `0`

After the app is running, use:

- `ASSET` to review integrity and trigger the built-in asset downloader when base assets are missing
- `SYNC` to refresh the model catalog after adding or changing `.pth` / `.index` files

### 3. Inspect the available command surface

```bash
make help
```

### 4. Run the shared development gate

```bash
make dev-check
```

### 5. Build the packaged app

```bash
make package
```

Expected artifact:

```text
dist/SwiftRVCMacClient.app
```

### 6. Inspect or launch the packaged app

```bash
make app-info
make run-app
```

### 7. Verify the app is ready to convert

On first launch, the minimum ready sequence is:

1. `BOOT` the backend
2. open `ASSET` and confirm the base inference assets are available
3. press `SYNC` so the app refreshes the available model list
4. select a voice model from the patch area

If no model appears in the app:

1. confirm `git submodule update --init --recursive` has been run
2. check that `engine/assets/weights/` contains at least one `.pth`
3. press `SYNC` again after adding files
4. open `ASSET` if the app still reports missing base resources

### 8. Run the local release gate when preparing a handoff

```bash
make release-check
```

## Common Commands

| Command | Purpose |
| --- | --- |
| `make help` | Show the current command index |
| `make status` | Show root repository status |
| `make engine-status` | Show nested `engine/` repository status |
| `make dev-check` | Run the shared development validation gate |
| `make package` | Build `dist/SwiftRVCMacClient.app` and print the app summary |
| `make app-info` | Print packaged app metadata and size summary |
| `make run-app` | Launch the packaged app from `dist/` |
| `make release-check` | Run the local release gate and verify the app bundle |

## Architecture / Repository Layout

MACR0VC keeps the desktop client, Python engine, and packaging workflow clearly separated.

```text
MACR0VC/
├── mac-client/   # SwiftPM macOS client
├── engine/       # Python FastAPI voice engine and realtime/audio pipeline
├── scripts/      # packaging, validation, and workflow helpers
├── docs/         # project and workflow documentation
├── dist/         # packaged app outputs and screenshots
├── Makefile      # preferred local entrypoints
└── AGENTS.md     # repository-specific operating rules
```

### Main subsystems

- `mac-client/`
  Swift desktop interface, application state, bridge client, and app packaging resources
- `engine/`
  FastAPI phase1 backend, realtime voice conversion controller, runtime management, and audio tooling
- `scripts/`
  Build, packaging, version-sync, and release validation helpers

## Workflow Highlights

### Desktop-first operation

The project is centered on a packaged macOS app rather than a browser-first control surface. The packaged target is:

```text
dist/SwiftRVCMacClient.app
```

### Realtime is opt-in

Realtime voice conversion is treated as an explicit workflow, not a default startup behavior. Offline voice conversion and text-driven generation remain the default accessible flows when realtime is idle.

### Shared operational commands

The repository already exposes a small command surface for daily work:

- development validation through `make dev-check`
- packaging through `make package`
- artifact inspection through `make app-info`
- smoke launch through `make run-app`
- release gating through `make release-check`

## Contribution

Contributions are welcome through:

- GitHub Issues for bug reports and workflow gaps
- Pull Requests for implementation changes
- Documentation improvements for onboarding and packaging
- Feedback on desktop voice workflows, realtime usability, and task visibility

When submitting changes, it helps to include:

- what changed
- why the change was needed
- how you validated it
- whether the packaged app or release gate was re-run

## License / Usage Restrictions

This repository is licensed under `PolyForm Noncommercial 1.0.0`.

- Commercial use is not allowed
- The full license text is available in the top-level [`LICENSE`](./LICENSE) file
- Use, sharing, and modification should follow the restrictions defined by `PolyForm Noncommercial 1.0.0`

This README intentionally avoids calling the project OSI-style open source because the selected license prohibits commercial use.

## Repository Links

- GitHub: [boogieLing/MACR0VC](https://github.com/boogieLing/MACR0VC)
- Issues: [github.com/boogieLing/MACR0VC/issues](https://github.com/boogieLing/MACR0VC/issues)
- Pull Requests: [github.com/boogieLing/MACR0VC/pulls](https://github.com/boogieLing/MACR0VC/pulls)
- SSH Clone: `git@github.com:boogieLing/MACR0VC.git`

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=boogieLing/MACR0VC&type=Date)](https://star-history.com/#boogieLing/MACR0VC&Date)
