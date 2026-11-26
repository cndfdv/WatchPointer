# Chrome tab switching acceptance test

This opt-in test sends real macOS accessibility actions to Chrome. Run it only when you can dedicate a Chrome window to the fixture tabs. It never opens tabs; it only sends a switch while the active window title identifies one of these exact fixture tabs.

1. Open `fixture.html?tab=1`, `fixture.html?tab=2`, and `fixture.html?tab=3` as three tabs in one Chrome window, in that order. Use the absolute file URL for the fixture path. Do not place other tabs between the fixture tabs.
2. Select Tab 2 and leave that Chrome window available. The test requires macOS Accessibility and event-posting permission.
3. From the repository root, compile and run:

   ```sh
   mkdir -p .local
   swiftc Mac/Sources/WatchPointer/RemoteInput.swift Mac/tests/BrowserTabsAcceptance/main.swift -o .local/check-browser-tabs
   .local/check-browser-tabs
   ```

The test checks revocation before input, then switches previous and next across the three fixture tabs and verifies each active tab title before sending the next action. It leaves Chrome on Tab 1.
