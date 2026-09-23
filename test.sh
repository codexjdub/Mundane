#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

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
