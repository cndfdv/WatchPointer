# Contributing to WatchPointer

Use [GitHub Issues](https://github.com/cndfdv/WatchPointer/issues) for bugs and feature requests. For bugs, include the WatchPointer version, Apple Watch model, macOS and watchOS versions, and what you saw on each device. Use [SECURITY.md](SECURITY.md) to report security issues privately.

Open a pull request with the behavior change and the checks you ran. For gesture changes, mention whether a physical Apple Watch and Mac were used. Keep local signing settings, keys, and app bundles out of commits.

Run the checks from the repository root:

```sh
swift test --package-path Mac
Watch/tests/test-pad-gesture.sh
Watch/tests/test-input-exchange.sh
Mac/tests/test-app-bundle.sh
```

Build the watch target without signing to check it on a Mac with the watchOS SDK:

```sh
xcodebuild -project Watch/WatchPointer.xcodeproj -scheme WatchPointer \
  -destination 'generic/platform=watchOS' -derivedDataPath .local/watch-build \
  CODE_SIGNING_ALLOWED=NO build
```

For a live browser-tab check on a Mac, see [the Chrome acceptance test](Mac/tests/BrowserTabsAcceptance/README.md).
