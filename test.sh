#!/bin/bash
# Runs the test suite. Extra arguments go to `swift test` (e.g. --filter TailTests).
set -euo pipefail
cd "$(dirname "$0")"
FLAGS=()
DEV="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEV" == *CommandLineTools* ]]; then
  # Command Line Tools ship swift-testing outside the default search path and without its
  # Foundation overlay module, so point the compiler and linker at it and skip the overlay.
  F="$DEV/Library/Developer/Frameworks"
  FLAGS=(-Xswiftc -F -Xswiftc "$F" -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
         -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F")
fi
swift test ${FLAGS[@]+"${FLAGS[@]}"} "$@"
