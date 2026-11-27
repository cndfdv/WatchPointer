# Contributing to WatchPointer

Use [GitHub Issues](https://github.com/cndfdv/WatchPointer/issues) for bugs and feature requests. For a bug, include the WatchPointer versions on each device, the Apple Watch model, the macOS and watchOS versions, and what appeared on each device. Report vulnerabilities privately. [Security reporting](SECURITY.md)

Open a pull request with the behavior change and the checks you ran. Keep local signing settings, input keys, logs, and app bundles out of commits.

## Automated checks

Run these commands from the repository root.

```sh
swift test --package-path Mac
Watch/tests/test-pad-gesture.sh
Watch/tests/test-input-exchange.sh
Mac/tests/test-app-bundle.sh
```

To compile the watch target with the watchOS SDK, build it without signing.

```sh
xcodebuild -project Watch/WatchPointer.xcodeproj -scheme WatchPointer \
  -destination 'generic/platform=watchOS' -derivedDataPath .local/watch-build \
  CODE_SIGNING_ALLOWED=NO build
```

## Checks on Apple Watch and Mac

Say which checks you ran on a physical watch. Use a scratch document or draft for dictation testing.

| Area | Check |
| --- | --- |
| Pointer and scroll | Center the pointer, click, and scroll a long document both ways with one finger. |
| Tabs | Open two tabs in a supported browser and switch both ways with one finger. [Chrome test instructions](Mac/tests/BrowserTabsAcceptance/README.md) |
| Spaces | Open a second desktop or a full-screen app. Use horizontal two-finger swipes to move to the neighboring Space and back. |
| Mission Control | Swipe up with two fingers, point at a window, and tap the watch pad to select it. |
| Dictation | Dictate into a focused scratch field. Repeat with the flow started in one field and finished after switching focus to another. Confirm that the new field stays unchanged and the watch retains the draft. |
