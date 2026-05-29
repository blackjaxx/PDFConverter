#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PDFConverter"
VOLUME_NAME="PDF Converter"
VERSION="${VERSION:-snapshot}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${PROJECT_DIR}"

DERIVED_DATA="build/derivedData"
EXPORT_DIR="build/export"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
STAGING_DIR="build/dmg_staging"

mkdir -p "${EXPORT_DIR}" "${STAGING_DIR}"

echo "==> Bundling CLI tools..."
if [ -f Scripts/bundle-tools.sh ]; then
    bash Scripts/bundle-tools.sh
fi

echo "==> Building Release..."
xcodebuild build \
    -project PDFConverter.xcodeproj \
    -scheme PDFConverter \
    -configuration Release \
    -derivedDataPath "${DERIVED_DATA}" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

APP_PATH="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: .app not found at $APP_PATH"
    find build/derivedData -name "*.app" -type d 2>/dev/null || true
    exit 1
fi

echo "==> Extracting .app bundle..."
cp -R "${APP_PATH}" "${EXPORT_DIR}/"

echo "==> Preparing DMG staging directory..."
cp -R "${EXPORT_DIR}/${APP_NAME}.app" "${STAGING_DIR}/"
ln -sf /Applications "${STAGING_DIR}/Applications"

echo "==> Creating DMG disk image..."
hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_NAME}"

echo "==> Cleaning up..."
rm -rf "${STAGING_DIR}"

echo "==> Done: ${DMG_NAME}"
ls -lh "${DMG_NAME}"