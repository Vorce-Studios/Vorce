#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${1:-0.0.0-dev}"
APP_DIR="${2:-$ROOT_DIR/target/release/Vorce.app}"
OUTPUT_DMG="${3:-Vorce-${VERSION}-macOS.dmg}"

if [[ ! -d "${APP_DIR}" ]]; then
    echo "Expected app bundle at ${APP_DIR}" >&2
    exit 1
fi

echo "Packaging ${APP_DIR} into ${OUTPUT_DMG}..."

# hdiutil needs a source folder. We'll use a temp directory to also include the Applications symlink.
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

cp -a "${APP_DIR}" "${TMP_DIR}/"
ln -s /Applications "${TMP_DIR}/Applications"

hdiutil create -volname "Vorce ${VERSION}" -srcfolder "${TMP_DIR}" -ov -format UDZO "${OUTPUT_DMG}"

echo "Successfully created ${OUTPUT_DMG}"
