#!/usr/bin/env bash
set -euo pipefail

TARGET_PATH="${1:-}"

if [[ -z "${TARGET_PATH}" ]]; then
    echo "Usage: $0 <path-to-app-or-dmg>" >&2
    exit 1
fi

if [[ ! -e "${TARGET_PATH}" ]]; then
    echo "Error: Target not found at ${TARGET_PATH}" >&2
    exit 1
fi

if [[ -z "${APPLE_DEV_ID:-}" ]]; then
    echo "Skipping signing: APPLE_DEV_ID environment variable is not set."
    exit 0
fi

if [[ "${TARGET_PATH}" == *.app ]]; then
    echo "Signing app bundle at ${TARGET_PATH}..."
    codesign --deep --force --options runtime --sign "${APPLE_DEV_ID}" "${TARGET_PATH}"
    echo "App bundle signed successfully."
elif [[ "${TARGET_PATH}" == *.dmg ]]; then
    echo "Signing DMG at ${TARGET_PATH}..."
    codesign --force --sign "${APPLE_DEV_ID}" "${TARGET_PATH}"
    echo "DMG signed successfully."

    if [[ -z "${APPLE_ID:-}" ]] || [[ -z "${APPLE_TEAM_ID:-}" ]] || [[ -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
        echo "Skipping notarization: APPLE_ID, APPLE_TEAM_ID, or APPLE_APP_SPECIFIC_PASSWORD environment variables are not set."
        exit 0
    fi

    echo "Notarizing DMG..."
    xcrun notarytool submit "${TARGET_PATH}" \
        --apple-id "${APPLE_ID}" \
        --team-id "${APPLE_TEAM_ID}" \
        --password "${APPLE_APP_SPECIFIC_PASSWORD}" \
        --wait

    echo "Stapling notarization ticket to DMG..."
    xcrun stapler staple "${TARGET_PATH}"
    echo "Notarization complete."
else
    echo "Error: Unsupported target type. Must be .app or .dmg." >&2
    exit 1
fi
