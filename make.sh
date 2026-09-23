#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP="Mundane"
BUNDLE="$APP.app"
BUNDLE_ID="com.mundane.Mundane"

# Signing identity lives in a gitignored Local.sh so it never reaches the repo.
# Absent that file, fall back to ad-hoc so a fresh clone still builds.
# shellcheck source=/dev/null
[ -f Local.sh ] && source Local.sh
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

# A release build signs ad-hoc whatever Local.sh says: a self-signed certificate is
# a trust anchor only in the keychain that made it, so it buys a downloader no trust
# while tying a public artifact to a personal cert.
[ "${1:-}" = "release" ] && SIGN_IDENTITY="-"

# Build outside the project directory for the same reason test.sh does: this tree
# is under a file provider that adds extended attributes, which breaks codesigning
# and leaves sync-conflict copies like ".build/out 2" behind.
SCRATCH="${TMPDIR%/}/mundane-build"

# ./make.sh icon — regenerate Resources/Mundane.icns.
# swiftc, not `swift Tools/make-icon.swift`, because the tool is compiled together
# with Palette.swift so it uses the app's own colours.
if [ "${1:-}" = "icon" ]; then
    mkdir -p "${TMPDIR%/}/mundane-build"
    swiftc -O -o "${TMPDIR%/}/mundane-build/make-icon" \
        Tools/MakeIcon/main.swift Sources/Mundane/Palette.swift
    "${TMPDIR%/}/mundane-build/make-icon"
    exit 0
fi

if [ "${1:-}" = "screenshot" ]; then
    mkdir -p "${TMPDIR%/}/mundane-build"
    swiftc -O -o "${TMPDIR%/}/mundane-build/shot" \
        Tools/Screenshot/main.swift \
        $(ls Sources/Mundane/*.swift | grep -v '/main\.swift$')
    "${TMPDIR%/}/mundane-build/shot"
    exit 0
fi

echo "==> build"
if [ "${1:-}" = "release" ]; then
    # Universal, so Intel Macs are covered. Kept out of everyday builds: two slices
    # double the compile, and multi-arch relocates the product out of release/.
    swift build -c release --scratch-path "$SCRATCH" --arch arm64 --arch x86_64
    BIN="$SCRATCH/out/Products/Release/$APP"
else
    swift build -c release --scratch-path "$SCRATCH"
    BIN="$SCRATCH/release/$APP"
fi

# Assemble, sign and verify in $TMPDIR, never in the project directory.
# codesign --strict rejects com.apple.FinderInfo, and this tree lives under a file
# provider (iCloud-synced Documents) that re-adds it moments after it is cleared —
# including between signing and verifying. Clearing xattrs twice only narrowed that
# race; staging outside the synced tree removes it. The finished bundle is copied
# in afterwards, by which point the signature is already verified.
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGE="$STAGE_DIR/$BUNDLE"

echo "==> assemble $BUNDLE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN" "$STAGE/Contents/MacOS/$APP"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
cp Resources/Mundane.icns "$STAGE/Contents/Resources/Mundane.icns"

echo "==> sign as '$SIGN_IDENTITY'"
xattr -cr "$STAGE"
codesign --force --options runtime -s "$SIGN_IDENTITY" "$STAGE"
codesign --verify --strict "$STAGE"

rm -rf "$BUNDLE"
ditto "$STAGE" "$BUNDLE"
echo "==> $BUNDLE ready"

# ./make.sh release — zip the signed bundle for a GitHub release. ditto -c -k
# --keepParent, not zip(1), which mangles a bundle's symlinks and signature.
# The download is quarantined either way; without Developer ID and notarization
# its first launch needs Privacy & Security -> Open Anyway, as the README says.
if [ "${1:-}" = "release" ]; then
    VERSION=$(defaults read "$PWD/Resources/Info" CFBundleShortVersionString)
    ZIP="$APP-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$STAGE" "$ZIP"
    echo "==> $ZIP ($(lipo -archs "$STAGE/Contents/MacOS/$APP"))"
fi

# ./make.sh install  — also place it in /Applications.
# Not required for launch at login: SMAppService reports "notFound" simply because
# nothing is registered yet, from any location, and registering works fine from a
# project directory. The real reason to install is that a rebuild here deletes and
# recreates the bundle a login item points at.
if [ "${1:-}" = "install" ]; then
    DEST="/Applications/$BUNDLE"

    # Only ever replace our own app, in case APP/BUNDLE is ever wrong.
    if [ -e "$DEST" ]; then
        EXISTING=$(defaults read "$DEST/Contents/Info" CFBundleIdentifier 2>/dev/null || echo "")
        if [ "$EXISTING" != "$BUNDLE_ID" ]; then
            echo "refusing to replace $DEST: bundle id '$EXISTING', expected '$BUNDLE_ID'" >&2
            exit 1
        fi
    fi

    echo "==> install to $DEST"
    pkill -x "$APP" 2>/dev/null || true
    rm -rf "$DEST"
    ditto "$STAGE" "$DEST"        # from the staged copy, which is already verified
    codesign --verify --strict "$DEST"
    echo "==> installed — enable Launch at Login from the /Applications copy"
fi
