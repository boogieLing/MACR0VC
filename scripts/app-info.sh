#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${ROOT_DIR}/dist/SwiftRVCMacClient.app"
PLIST_PATH="${APP_PATH}/Contents/Info.plist"
EXECUTABLE_PATH="${APP_PATH}/Contents/MacOS/SwiftRVCMacClient"
PHASE1_API_PATH="${ROOT_DIR}/engine/phase1_api.py"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "[app-info] missing app bundle: ${APP_PATH}" >&2
  exit 1
fi

if [[ ! -f "${PLIST_PATH}" ]]; then
  echo "[app-info] missing Info.plist: ${PLIST_PATH}" >&2
  exit 1
fi

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
  echo "[app-info] missing executable: ${EXECUTABLE_PATH}" >&2
  exit 1
fi

read_plist_value() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Print :${key}" "${PLIST_PATH}"
}

BUNDLE_ID="$(read_plist_value CFBundleIdentifier)"
VERSION="$(read_plist_value CFBundleShortVersionString)"
BUILD_NUMBER="$(read_plist_value CFBundleVersion)"
MIN_SYSTEM_VERSION="$(read_plist_value LSMinimumSystemVersion)"
EXECUTABLE_NAME="$(read_plist_value CFBundleExecutable)"
BUNDLE_SIZE="$(du -sh "${APP_PATH}" | awk '{print $1}')"
EXECUTABLE_SIZE="$(du -sh "${EXECUTABLE_PATH}" | awk '{print $1}')"
MODIFIED_AT="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S %z' "${APP_PATH}")"
BACKEND_API_VERSION="$(python3 - <<'PY' "${PHASE1_API_PATH}"
from pathlib import Path
import re
import sys
content = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r'^BACKEND_API_VERSION = "(.*)"$', content, flags=re.MULTILINE)
print(match.group(1) if match else "")
PY
)"
BACKEND_BUILD_VERSION="$(python3 - <<'PY' "${PHASE1_API_PATH}"
from pathlib import Path
import re
import sys
content = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r'^BACKEND_BUILD_VERSION = "(.*)"$', content, flags=re.MULTILINE)
print(match.group(1) if match else "")
PY
)"

printf "App Bundle Summary\n"
printf "  Path: %s\n" "${APP_PATH}"
printf "  Bundle ID: %s\n" "${BUNDLE_ID}"
printf "  Version: %s (%s)\n" "${VERSION}" "${BUILD_NUMBER}"
printf "  Executable: %s\n" "${EXECUTABLE_NAME}"
printf "  Minimum macOS: %s\n" "${MIN_SYSTEM_VERSION}"
printf "  Backend API Version: %s\n" "${BACKEND_API_VERSION}"
printf "  Backend Build Version: %s\n" "${BACKEND_BUILD_VERSION}"
printf "  Bundle Size: %s\n" "${BUNDLE_SIZE}"
printf "  Executable Size: %s\n" "${EXECUTABLE_SIZE}"
printf "  Modified At: %s\n" "${MODIFIED_AT}"

if command -v codesign >/dev/null 2>&1; then
  SIGNING_IDENTITY="$(codesign -dv "${APP_PATH}" 2>&1 | awk -F= '/^Authority=/{print $2; exit}')"
  if [[ -n "${SIGNING_IDENTITY}" ]]; then
    printf "  Signing Authority: %s\n" "${SIGNING_IDENTITY}"
  else
    printf "  Signing Authority: ad-hoc or unavailable\n"
  fi
fi
