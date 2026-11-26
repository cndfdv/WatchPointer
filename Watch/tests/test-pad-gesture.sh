#!/bin/bash
set -euo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/watchpointer-pad-test.XXXXXXXX")
trap 'rm -rf -- "$temp_dir"' EXIT

xcrun --sdk macosx swiftc "$tests_dir/../WatchPointer/PadGesture.swift" \
    "$tests_dir/PadGestureTests/main.swift" -o "$temp_dir/pad-gesture-tests"
"$temp_dir/pad-gesture-tests"
