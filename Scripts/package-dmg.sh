#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PDFConverter"
VOLUME_NAME="PDF Converter"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${PROJECT_DIR}"

ARCHIVE_PATH="build/${APP_NAME}.xcarchive"
EXPORT_DIR="build/export"
DMG_NAME="${APP_NAME}-${VERSION:-snapshot}.dmg"
STAGING_DIR="build/dmg_staging"

mkdir -p "${EXPORT_DIR}" "${STAGING_DIR}"

echo "==> Bundling CLI tools..."
if [ -f Scripts/bundle-tools.sh ]; then
    bash Scripts/bundle-tools.sh
fi

echo "==> Resolving Swift Package dependencies..."
(cd Packages/PDFConverterCore && swift package resolve)

echo "==> Building Release archive..."
xcodebuild archive \
    -project PDFConverter.xcodeproj \
    -scheme PDFConverter \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

echo "==> Exporting .app bundle..."
cp -R "${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app" "${EXPORT_DIR}/"

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