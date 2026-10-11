#!/bin/bash
# DiskDude 1.0.1 — full build pipeline (macOS)
#
# Reconstructs the shipping artifact from source:
#   source → xcodebuild → DiskDude.app → UDZO DMG
#
# The DMG packaging parameters were recovered from the shipped
# DiskDude-1.0.1.dmg (see tools/rebuild_dmg.py for the byte-level analysis):
#   - UDIF UDZO, zlib level 1 (verified: every chunk recompresses
#     byte-identically at level 1)
#   - GPT-wrapped HFS+ image, 15,723 sectors total, Apple_HFS partition
#     at sector 40
#   - layout: [DiskDude.app, Applications symlink] at volume root
#
# Usage:  ./build.sh [output.dmg]
set -euo pipefail

APP_NAME="DiskDude"
APP_VERSION="1.0.1"
SCHEME="DiskDude"
CONFIG="Release"
OUT_DMG="${1:-DiskDude-${APP_VERSION}.dmg}"
VOL_NAME="DiskDude"

# ---- 1. Build the app (requires Xcode 16+ / SDK 26, Swift 6) ----
xcodebuild \
  -project DiskDude.xcodeproj \
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  build

APP_PATH="build/Build/Products/${CONFIG}/${APP_NAME}.app"
test -d "${APP_PATH}"

# ---- 2. Stage the DMG root: app + Applications symlink ----
STAGE="$(mktemp -d)/${VOL_NAME}"
mkdir -p "${STAGE}"
cp -R "${APP_PATH}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"

# ---- 3. Create the UDZO DMG (zlib level 1 = hdiutil UDZO default) ----
hdiutil create \
  -volname "${VOL_NAME}" \
  -srcfolder "${STAGE}" \
  -format UDZO \
  -ov \
  "${OUT_DMG}"

echo "Built ${OUT_DMG}"
shasum -a 256 "${OUT_DMG}"
