#!/bin/bash
set -euo pipefail

mac_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
repo_dir=$(dirname -- "$mac_dir")
temp_root=$(mktemp -d "${TMPDIR:-/tmp}/watchpointer-app-bundle-test.XXXXXXXX")
output_dir="$temp_root/output with spaces"
app_path="$output_dir/WatchPointer.app"

cleanup() {
    rm -rf -- "$temp_root"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$output_dir"
"$mac_dir/build-app.sh" "$output_dir"

executable="$app_path/Contents/MacOS/WatchPointer"
info_plist="$app_path/Contents/Info.plist"
icon="$app_path/Contents/Resources/WatchPointer.icns"
bundled_license="$app_path/Contents/Resources/LICENSE"

[[ -x "$executable" ]] || { printf 'Missing executable: %s\n' "$executable" >&2; exit 1; }
[[ -s "$icon" ]] || { printf 'Missing or empty app icon: %s\n' "$icon" >&2; exit 1; }
[[ -f "$bundled_license" ]] || { printf 'Missing bundled license: %s\n' "$bundled_license" >&2; exit 1; }
cmp -s -- "$repo_dir/LICENSE" "$bundled_license" || {
    printf 'Bundled license differs from repository LICENSE\n' >&2
    exit 1
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$info_plist"
}

[[ "$(plist_value CFBundlePackageType)" == APPL ]] || {
    printf 'CFBundlePackageType must be APPL\n' >&2
    exit 1
}
[[ "$(plist_value LSUIElement)" == true ]] || {
    printf 'LSUIElement must be true for a menu bar app\n' >&2
    exit 1
}
[[ "$(plist_value NSBluetoothAlwaysUsageDescription)" == "Receives pointer movement and approved input from your Apple Watch." ]] || {
    printf 'Unexpected Bluetooth usage description\n' >&2
    exit 1
}

codesign --verify --strict "$app_path"

# A second install must fail without replacing the already-built app bundle.
ditto "$app_path" "$temp_root/WatchPointer-before-rerun.app"
if "$mac_dir/build-app.sh" "$output_dir" >"$temp_root/rerun.log" 2>&1; then
    printf 'Build unexpectedly replaced an existing app bundle\n' >&2
    exit 1
fi
diff -r "$temp_root/WatchPointer-before-rerun.app" "$app_path" >/dev/null || {
    printf 'Existing app bundle changed after a rejected rebuild\n' >&2
    exit 1
}
grep -Fq 'App already exists:' "$temp_root/rerun.log" || {
    printf 'Rebuild failed for an unexpected reason:\n' >&2
    cat "$temp_root/rerun.log" >&2
    exit 1
}

printf 'App bundle packaging checks passed.\n'
