#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_DIR="${ROOT_DIR}/mac-client"
DIST_DIR="${ROOT_DIR}/dist"
APP_NAME="SwiftRVCMacClient"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
EXECUTABLE_PATH="${CLIENT_DIR}/.build/arm64-apple-macosx/release/${APP_NAME}"
ICON_SOURCE_PATH="${ROOT_DIR}/logo.png"
ICON_NAME="AppIcon"
ICON_FILE_NAME="${ICON_NAME}.icns"
ICON_BASE_SIZE=1024
ICON_INSET_SIZE=860
ICON_CORNER_RADIUS=180

mkdir -p "${DIST_DIR}"

pushd "${CLIENT_DIR}" >/dev/null
swift build -c release --product "${APP_NAME}"
popd >/dev/null

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

if [[ -f "${ICON_SOURCE_PATH}" ]]; then
  ICONSET_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/${ICON_NAME}.XXXXXX")"
  ICONSET_DIR="${ICONSET_ROOT}/${ICON_NAME}.iconset"
  PROCESSED_ICON_PATH="${ICONSET_ROOT}/logo-processed.png"
  mkdir -p "${ICONSET_DIR}"

  if command -v magick >/dev/null 2>&1; then
    magick \
      -size "${ICON_BASE_SIZE}x${ICON_BASE_SIZE}" xc:none \
      \( "${ICON_SOURCE_PATH}" -resize "${ICON_INSET_SIZE}x${ICON_INSET_SIZE}" \) \
      -gravity center -composite \
      \( -size "${ICON_BASE_SIZE}x${ICON_BASE_SIZE}" xc:none -fill white -draw "roundrectangle $(((ICON_BASE_SIZE - ICON_INSET_SIZE) / 2)),$(((ICON_BASE_SIZE - ICON_INSET_SIZE) / 2)) $(((ICON_BASE_SIZE + ICON_INSET_SIZE) / 2 - 1)),$(((ICON_BASE_SIZE + ICON_INSET_SIZE) / 2 - 1)) ${ICON_CORNER_RADIUS},${ICON_CORNER_RADIUS}" \) \
      -compose DstIn -composite \
      "${PROCESSED_ICON_PATH}"
  else
    cp "${ICON_SOURCE_PATH}" "${PROCESSED_ICON_PATH}"
  fi

  generate_icon() {
    local size="$1"
    local output_name="$2"
    sips -z "${size}" "${size}" "${PROCESSED_ICON_PATH}" --out "${ICONSET_DIR}/${output_name}" >/dev/null
  }

  generate_icon 16 "icon_16x16.png"
  generate_icon 32 "icon_16x16@2x.png"
  generate_icon 32 "icon_32x32.png"
  generate_icon 64 "icon_32x32@2x.png"
  generate_icon 128 "icon_128x128.png"
  generate_icon 256 "icon_128x128@2x.png"
  generate_icon 256 "icon_256x256.png"
  generate_icon 512 "icon_256x256@2x.png"
  generate_icon 512 "icon_512x512.png"
  cp "${PROCESSED_ICON_PATH}" "${ICONSET_DIR}/icon_512x512@2x.png"

  iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/${ICON_FILE_NAME}"
  rm -rf "${ICONSET_ROOT}"
fi

cat > "${CONTENTS_DIR}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SwiftRVCMacClient</string>
    <key>CFBundleIdentifier</key>
    <string>local.r0.SwiftRVCMacClient</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>SwiftRVCMacClient</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "${CONTENTS_DIR}/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || true
fi

echo "${APP_DIR}"
