#!/bin/bash
set -euo pipefail
umask 077

if (( $# != 1 )); then
    printf 'Usage: %s output-directory\n' "$0" >&2
    exit 2
fi

root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
cd -- "$root"
config="$root/.local/watch-signing.xcconfig"
key="$root/.local/WatchPointerInput.bin"
[[ -f "$config" ]] || { printf 'Missing local Watch signing configuration.\n' >&2; exit 1; }

mkdir -p -- "$1"
output=$(CDPATH= cd -- "$1" && pwd -P)
case "$output/" in
    "$root/.local/"*) ;;
    *) printf 'Choose an output directory inside the ignored .local folder.\n' >&2; exit 1 ;;
esac
[[ ! -e "$output/LocalWatchPointer" && ! -L "$output/LocalWatchPointer" ]] || {
    printf 'LocalWatchPointer already exists in the output directory.\n' >&2
    exit 1
}

python3 - "$key" <<'PY'
import os
import stat
import sys

path = sys.argv[1]
try:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
except FileExistsError:
    pass
else:
    with os.fdopen(descriptor, 'wb') as file:
        file.write(os.urandom(32))
info = os.lstat(path)
if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077 or info.st_size != 32:
    raise SystemExit('The local input key must be one private 32-byte file owned by the current user.')
PY

stage=$(mktemp -d "$output/.watchpointer-local.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

project="$stage/source/Watch/WatchPointer.xcodeproj"
shared="$stage/source/Mac/Sources/WatchPointer"
mkdir -p -- "$project" "$shared" "$stage/LocalWatchPointer/Mac" "$stage/LocalWatchPointer/Watch"
cp "$root/Watch/WatchPointer.xcodeproj/project.pbxproj" "$project/"
cp -R "$root/Watch/WatchPointer" "$stage/source/Watch/"
cp "$root/Mac/Sources/WatchPointer/LocalInputCipher.swift" "$shared/"
install -m 600 "$key" "$stage/source/Watch/WatchPointer/WatchPointerInput.bin"

xcrun xcodebuild -project "$project" -scheme WatchPointer \
    -destination "${WATCHPOINTER_WATCH_DESTINATION:-generic/platform=watchOS}" \
    -derivedDataPath "$stage/derived" -xcconfig "$config" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration -quiet build
watch_app="$stage/derived/Build/Products/Debug-watchos/WatchPointer.app"
[[ -s "$watch_app/WatchPointerInput.bin" ]] || { printf 'Watch key resource missing.\n' >&2; exit 1; }
codesign --verify --strict "$watch_app"
mv -- "$watch_app" "$stage/LocalWatchPointer/Watch/"

"$root/Mac/build-app.sh" "$stage/LocalWatchPointer/Mac"
mac_app="$stage/LocalWatchPointer/Mac/WatchPointer.app"
install -m 600 "$key" "$mac_app/Contents/Resources/WatchPointerInput.bin"
codesign --force --sign "${WATCHPOINTER_MAC_SIGN_IDENTITY:-Apple Development}" "$mac_app"
codesign --verify --strict "$mac_app"

mv -n -- "$stage/LocalWatchPointer" "$output/"
[[ ! -e "$stage/LocalWatchPointer" ]] || { printf 'LocalWatchPointer output appeared during the build.\n' >&2; exit 1; }
printf 'Built matching local apps in %s\n' "$output/LocalWatchPointer"
