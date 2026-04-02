#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${ROOT_DIR}/dist/SwiftRVCMacClient.app"
PLIST_PATH="${APP_PATH}/Contents/Info.plist"
EXECUTABLE_PATH="${APP_PATH}/Contents/MacOS/SwiftRVCMacClient"
ICON_PATH="${APP_PATH}/Contents/Resources/AppIcon.icns"

echo "[release-check] running shared validation"
bash "${ROOT_DIR}/scripts/dev-check.sh"

echo "[release-check] rebuilding packaged app"
PACKAGE_OUTPUT="$(bash "${ROOT_DIR}/scripts/build-macos-app.sh")"
echo "[release-check] package output: ${PACKAGE_OUTPUT}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "[release-check] missing app bundle: ${APP_PATH}" >&2
  exit 1
fi

if [[ ! -f "${PLIST_PATH}" ]]; then
  echo "[release-check] missing Info.plist: ${PLIST_PATH}" >&2
  exit 1
fi

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
  echo "[release-check] missing executable: ${EXECUTABLE_PATH}" >&2
  exit 1
fi

if [[ ! -f "${ICON_PATH}" ]]; then
  echo "[release-check] missing icon: ${ICON_PATH}" >&2
  exit 1
fi

if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${PLIST_PATH}")"
  EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${PLIST_PATH}")"
  MIN_SYSTEM_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${PLIST_PATH}")"

  if [[ "${BUNDLE_ID}" != "local.r0.SwiftRVCMacClient" ]]; then
    echo "[release-check] unexpected bundle id: ${BUNDLE_ID}" >&2
    exit 1
  fi

  if [[ "${EXECUTABLE_NAME}" != "SwiftRVCMacClient" ]]; then
    echo "[release-check] unexpected executable name in plist: ${EXECUTABLE_NAME}" >&2
    exit 1
  fi

  if [[ "${MIN_SYSTEM_VERSION}" != "14.0" ]]; then
    echo "[release-check] unexpected minimum system version: ${MIN_SYSTEM_VERSION}" >&2
    exit 1
  fi
fi

if command -v codesign >/dev/null 2>&1; then
  echo "[release-check] verifying code signature"
  codesign --verify --deep --strict "${APP_PATH}"
fi

echo "[release-check] app bundle verified: ${APP_PATH}"
bash "${ROOT_DIR}/scripts/app-info.sh"
