#!/bin/bash
set -euo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/watchpointer-input-test.XXXXXXXX")
trap 'rm -rf -- "$temp_dir"' EXIT

xcrun --sdk macosx swiftc "$tests_dir/../WatchPointer/WatchInputExchange.swift" \
    "$tests_dir/InputExchangeTests/main.swift" -o "$temp_dir/input-exchange-tests"
"$temp_dir/input-exchange-tests"
