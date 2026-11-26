#!/bin/bash
set -euo pipefail

if (( $# > 1 )); then
    printf 'Usage: %s [output-directory]\n' "$0" >&2
    exit 2
fi

mac_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(dirname -- "$mac_dir")
output_dir=${1:-"$mac_dir/.build/app"}
mkdir -p -- "$output_dir"
output_dir=$(CDPATH= cd -- "$output_dir" && pwd -P)
app_path="$output_dir/WatchPointer.app"

if [[ -e "$app_path" || -L "$app_path" ]]; then
    printf 'App already exists: %s\n' "$app_path" >&2
    exit 1
fi

stage_dir=$(mktemp -d "$output_dir/.watchpointer-app.XXXXXXXX")
trap 'rm -rf -- "$stage_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cd -- "$mac_dir"
xcrun swift build --configuration release --product WatchPointer
bin_dir=$(xcrun swift build --configuration release --show-bin-path)

staged_app="$stage_dir/WatchPointer.app"
contents="$staged_app/Contents"
iconset="$stage_dir/WatchPointer.iconset"
mkdir -p -- "$contents/MacOS" "$contents/Resources" "$iconset"

install -m 755 "$bin_dir/WatchPointer" "$contents/MacOS/WatchPointer"
cp -- "$mac_dir/Sources/WatchPointer/Info.plist" "$contents/Info.plist"
cp -- "$repo_dir/LICENSE" "$contents/Resources/LICENSE"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$repo_dir/docs/icon.png" \
        --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" "$repo_dir/docs/icon.png" \
        --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$contents/Resources/WatchPointer.icns"

codesign --force --sign - "$staged_app"
codesign --verify --strict "$staged_app"

# Move into the parent so another build cannot turn app_path into a destination directory.
mv -n -- "$staged_app" "$output_dir/"
if [[ -e "$staged_app" ]]; then
    printf 'App already exists: %s\n' "$app_path" >&2
    exit 1
fi
printf 'Built %s\n' "$app_path"
