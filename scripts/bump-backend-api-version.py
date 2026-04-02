#!/usr/bin/env python3

from __future__ import annotations

import re
from datetime import datetime
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[1]
PHASE1_API_PATH = ROOT_DIR / "engine" / "phase1_api.py"
ENGINE_CONTROLLER_PATH = ROOT_DIR / "mac-client" / "Sources" / "SwiftRVCMacClient" / "Services" / "EngineController.swift"


def replace_once(content: str, pattern: str, replacement: str, path: Path) -> str:
    updated, count = re.subn(pattern, replacement, content, count=1, flags=re.MULTILINE)
    if count != 1:
        raise RuntimeError(f"Failed to update pattern {pattern!r} in {path}")
    return updated


def main() -> None:
    now = datetime.now()
    api_version = f"phase1-api-{now.strftime('%Y-%m-%d-%H%M%S')}"
    backend_build_version = now.strftime("%Y.%m.%d.%H%M%S")
    app_short_version = now.strftime("%Y.%m.%d")
    app_build_version = now.strftime("%Y%m%d%H%M%S")

    phase1_api = PHASE1_API_PATH.read_text(encoding="utf-8")
    phase1_api = replace_once(
        phase1_api,
        r'^BACKEND_API_VERSION = ".*"$',
        f'BACKEND_API_VERSION = "{api_version}"',
        PHASE1_API_PATH,
    )
    phase1_api = replace_once(
        phase1_api,
        r'^BACKEND_BUILD_VERSION = ".*"$',
        f'BACKEND_BUILD_VERSION = "{backend_build_version}"',
        PHASE1_API_PATH,
    )
    PHASE1_API_PATH.write_text(phase1_api, encoding="utf-8")

    engine_controller = ENGINE_CONTROLLER_PATH.read_text(encoding="utf-8")
    engine_controller = replace_once(
        engine_controller,
        r'^    private static let requiredAPIVersion = ".*"$',
        f'    private static let requiredAPIVersion = "{api_version}"',
        ENGINE_CONTROLLER_PATH,
    )
    ENGINE_CONTROLLER_PATH.write_text(engine_controller, encoding="utf-8")

    print(f"API_VERSION={api_version}")
    print(f"BACKEND_BUILD_VERSION={backend_build_version}")
    print(f"APP_SHORT_VERSION={app_short_version}")
    print(f"APP_BUILD_VERSION={app_build_version}")


if __name__ == "__main__":
    main()
