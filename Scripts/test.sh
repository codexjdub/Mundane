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

# Two things this needs that a plain `swift test` does not:
#
#   --scratch-path   keeps .build out of the project directory. This tree is under
#                    a file provider (iCloud-synced Documents) which adds extended
#                    attributes, and codesigning the test bundle then fails.
#   -plugin-path     Command Line Tools ships libTestingMacros.dylib in a testing/
#                    subdirectory, which is not on SwiftPM's default search path,
#                    so @Test does not resolve without pointing at it.
exec swift test \
    --scratch-path "${TMPDIR%/}/mundane-build" \
    -Xswiftc -plugin-path \
    -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
    "$@"
