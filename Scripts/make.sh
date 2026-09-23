#!/usr/bin/env bash
set -euo pipefail
# Resolve $0 through any symlinks before locating the project root, so the
# script still works when linked into a directory on PATH. Then assert we
# landed somewhere that is actually this package: without the check, a wrong
# cd silently builds whatever other Swift package happens to be there.
SELF="$0"
while [ -L "$SELF" ]; do
    LINK="$(readlink "$SELF")"
    case "$LINK" in /*) SELF="$LINK" ;; *) SELF="$(dirname "$SELF")/$LINK" ;; esac
done
cd "$(dirname "$SELF")/.."
[ -f Package.swift ] || { echo "not the project root: $PWD" >&2; exit 1; }

APP="Mundane"
BUNDLE="$APP.app"
BUNDLE_ID="com.mundane.Mundane"

# Every artifact this script produces goes here, gitignored, so the project root
# stays source-only. Distinct from SwiftPM's .build/, which never appears: the
# compile itself happens in $SCRATCH, outside the tree entirely.
OUT="build"

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

# Scripts/make.sh clean — drop both build trees. The universal build keeps two
# slices plus intermediates, which runs to hundreds of MB under $TMPDIR.
if [ "${1:-}" = "clean" ]; then
    rm -rf "$OUT" "$SCRATCH"
    echo "==> removed $OUT and $SCRATCH"
    exit 0
fi

# Scripts/make.sh icon — regenerate Resources/Mundane.icns.
# swiftc, not `swift Tools/make-icon.swift`, because the tool is compiled together
# with Palette.swift so it uses the app's own colours.
if [ "${1:-}" = "icon" ]; then
    mkdir -p "$SCRATCH"
    swiftc -O -o "$SCRATCH/make-icon" \
        Tools/MakeIcon/main.swift Sources/Mundane/Palette.swift
    "$SCRATCH/make-icon" "$OUT"
    exit 0
fi

if [ "${1:-}" = "screenshot" ]; then
    mkdir -p "$SCRATCH"
    swiftc -O -o "$SCRATCH/shot" \
        Tools/Screenshot/main.swift \
        $(ls Sources/Mundane/*.swift | grep -v '/main\.swift$')
    "$SCRATCH/shot"
    exit 0
fi

echo "==> build"
# Universal, so any build here runs on Apple silicon and Intel alike. The second
# slice costs about a second incrementally, which is not worth a separate release
# mode. Multi-arch relocates the product out of release/, hence the longer path.
# The toolchain warns x86_64 is deprecated "for your deployment target (macOS
# 27.0)". It is wrong about the target — Package.swift pins macOS 14 and vtool
# reports minos 14.0 on both slices — and it fires on every build, so it would
# bury a real warning. Filtered by exact text; everything else still shows.
swift build -c release --scratch-path "$SCRATCH" --arch arm64 --arch x86_64 2>&1 |
    { grep -v "The x86_64 architecture is deprecated" || true; }
BIN="$SCRATCH/out/Products/Release/$APP"

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

mkdir -p "$OUT"
rm -rf "$OUT/$BUNDLE"
ditto "$STAGE" "$OUT/$BUNDLE"
echo "==> $OUT/$BUNDLE ready"

# Scripts/make.sh release — zip the signed bundle for a GitHub release.
# ditto -c -k --keepParent, not zip(1), which mangles a bundle's symlinks
# and signature.
# The download is quarantined either way; without Developer ID and notarization
# its first launch needs Privacy & Security -> Open Anyway, as the README says.
if [ "${1:-}" = "release" ]; then
    VERSION=$(defaults read "$PWD/Resources/Info" CFBundleShortVersionString)
    TAG="v$VERSION"

    # Info.plist is the only source of the version. A tag of the same name on a
    # different commit means the two have diverged, and the release would carry
    # a zip whose name disagrees with its tag.
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 &&
       [ "$(git rev-parse "$TAG^{commit}")" != "$(git rev-parse HEAD)" ]; then
        echo "$TAG already exists on another commit — bump" \
             "CFBundleShortVersionString in Resources/Info.plist" >&2
        exit 1
    fi

    # Every past version, not just this one: leaving older zips here lets a
    # glob like build/*.zip attach a stale binary to the new release.
    rm -f "$OUT/$APP"-*.zip
    ZIP="$OUT/$APP-$VERSION.zip"
    ditto -c -k --keepParent "$STAGE" "$ZIP"

    # Verify the archive, not just the bundle that went into it: the zip is
    # what gets published, and a truncated one would otherwise reach a
    # stranger's Mac before anyone noticed.
    UNZIP_DIR="$STAGE_DIR/verify"
    mkdir -p "$UNZIP_DIR"
    ditto -x -k "$ZIP" "$UNZIP_DIR"
    codesign --verify --strict "$UNZIP_DIR/$BUNDLE"

    echo "==> $ZIP ($(lipo -archs "$STAGE/Contents/MacOS/$APP"))"
    echo "==> next: git tag -a $TAG -m \"$APP $VERSION\" && git push origin $TAG"
    echo "==>       gh release create $TAG $ZIP"
fi

# Scripts/make.sh install — also place it in /Applications.
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
