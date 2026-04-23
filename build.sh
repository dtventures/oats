#!/bin/bash
# build.sh — builds Oats.app and packages it into a distributable Oats.dmg
# Usage:
#   ./build.sh          → ad-hoc signed (no Apple Developer account needed)
#   ./build.sh --sign   → signs with your Developer ID if one is present
set -euo pipefail

APP_NAME="Oats"
BUNDLE_ID="com.oats.app"
ARCH="arm64"
BUILD_DIR=".build/${ARCH}-apple-macosx/release"
DIST_DIR="dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"
STAGING_DIR="${DIST_DIR}/dmg_staging"

# ── Code signing identity ──────────────────────────────────────────────────
SIGN_IDENTITY="-"   # ad-hoc by default
if [[ "${1:-}" == "--sign" ]]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning \
        | grep "Developer ID Application" \
        | head -1 \
        | awk -F'"' '{print $2}')
    if [[ -z "$SIGN_IDENTITY" ]]; then
        echo "No 'Developer ID Application' certificate found — falling back to ad-hoc signing."
        SIGN_IDENTITY="-"
    else
        echo "Signing with: $SIGN_IDENTITY"
    fi
fi

# ── 1. Build ───────────────────────────────────────────────────────────────
echo "→ Building release binary (${ARCH})…"
swift build -c release --arch "${ARCH}"

# ── 2. Create .app bundle structure ───────────────────────────────────────
echo "→ Assembling ${APP_NAME}.app…"
rm -rf "${DIST_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
mkdir -p "${APP_BUNDLE}/Contents/Frameworks"

# Binary
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Info.plist goes at Contents/ (not Resources/)
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# SPM resource bundle (contains OatIcon.png etc.)
cp -R "${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle" \
      "${APP_BUNDLE}/Contents/Resources/"

# App icon — must live directly in Contents/Resources/ and match CFBundleIconFile in Info.plist
cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

# ── 3. Code sign ──────────────────────────────────────────────────────────
echo "→ Code signing (identity: ${SIGN_IDENTITY})…"

codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"

echo "→ Verifying signature…"
codesign --verify --deep --strict "${APP_BUNDLE}" && echo "   Signature OK"

# ── 4. Strip quarantine so downloaders aren't blocked by Gatekeeper ───────
echo "→ Stripping quarantine attribute…"
xattr -cr "${APP_BUNDLE}"

# ── 5. Package DMG ────────────────────────────────────────────────────────
echo "→ Creating ${APP_NAME}.dmg…"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
ln -sf /Applications "${STAGING_DIR}/Applications"

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "${DMG_PATH}"

rm -rf "${STAGING_DIR}"

echo ""
echo "✓ Done!  →  ${DMG_PATH}"
echo ""
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "NOTE: This DMG is ad-hoc signed (no Apple Developer certificate)."
    echo "Users will see a Gatekeeper warning on first launch."
    echo "They can bypass it: right-click Oats.app → Open → Open."
    echo ""
    echo "To distribute without warnings, you need:"
    echo "  1. Apple Developer Program (\$99/yr) → developer.apple.com"
    echo "  2. A 'Developer ID Application' certificate in Keychain Access"
    echo "  3. Run:  ./build.sh --sign  then notarize with xcrun notarytool"
fi
