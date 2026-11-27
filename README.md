# WatchPointer

<img src="docs/icon.png" width="88" align="right" alt="">

Turn your Apple Watch into a Bluetooth pointer and remote for your Mac. Aim at the screen to move the cursor, use the watch pad to navigate, and dictate directly into a focused Mac text field.

The watch connects directly to your Mac over Bluetooth. WatchPointer runs without a server.

[Install](#install) · [Gestures](#gestures) · [Dictation](#dictation) · [Troubleshooting](#troubleshooting) · [Releases](https://github.com/cndfdv/WatchPointer/releases)

<p align="center">
  <img src="docs/demo.webp" width="360" alt="An Apple Watch held like a remote moves the pointer on a MacBook">
</p>

## Install

You need a Mac with **macOS 14 or later** and Bluetooth, an Apple Watch with **watchOS 11 or later**, and **Xcode 16 or later** to build and install the watch app. For the Mac app alone, the Xcode Command Line Tools are sufficient. Releases include source archives. The watch app uses your Apple development signing settings.

### 1. Build and launch the Mac app

Run these commands in **Terminal**.

```bash
git clone https://github.com/cndfdv/WatchPointer.git
cd WatchPointer
Mac/build-app.sh
open Mac/.build/app/WatchPointer.app
```

Allow **Bluetooth** when macOS prompts you. In the WatchPointer menu bar menu, choose **Open Accessibility Settings…** and enable WatchPointer. If macOS asks you to reopen it, choose **Quit WatchPointer** in the menu, then run the `open` command again.

### 2. Install the watch app

1. In the same Terminal window, run `open Watch/WatchPointer.xcodeproj`.
2. Select the **WatchPointer** target. In **Signing & Capabilities**, enable automatic signing, choose your Apple development team, and set a unique bundle identifier.
3. Select your Apple Watch as the run destination and press **⌘R**.
4. Open WatchPointer on the watch and tap **Pair** next to your Mac.

### 3. Aim and pair remote input

1. Hold the watch with its top edge at 12 o’clock facing the screen. Aim at the center of the display and tap **Center** on the watch.
2. On the Mac, choose **Pair Watch Input…** in the WatchPointer menu.
3. On the watch, open **Remote actions** (the ellipsis button), tap **Pair Watch Input**, and enter the six-digit code shown on the Mac. Confirm any system Bluetooth prompt.

The first pairing connects the watch to your Mac. The six-digit pairing authorizes browser tabs, Spaces, Mission Control, and dictation. Choose **Forget Watch Input** in the Mac menu to revoke that authorization.

## Gestures

Use the large pad on the main watch screen.

| On the watch | On the Mac |
| --- | --- |
| Tap | Left-click |
| Hold, move the watch, then lift your finger | Drag and drop |
| Swipe one finger up or down, or turn the Digital Crown | Scroll under the pointer |
| Swipe one finger left or right | Next or previous tab in a supported browser |
| Swipe two fingers left or right | Next or previous macOS Space, including full-screen apps |
| Swipe two fingers up | Open Mission Control. Point at a window and tap to select it |

For two-finger gestures, put both fingertips on the pad and move them together. The watch also has buttons for right-clicking, centering the aim, pausing, and dictating.

## Dictation

1. Click where you want the text on your Mac. For example, click in a TextEdit document or the Codex chat composer.
2. Tap the **microphone** on the main watch screen. Dictate with the watch’s system text input and confirm.
3. Keep the same Mac field focused until the text appears. The session lasts two minutes. In a chat, the text goes into the composer as a draft.

If focus changes, open **Remote actions** to recover the draft. If the watch asks you to check the Mac before resending, see whether the text already appeared. Then focus the intended field and tap **Send** on the watch if needed. **Dictate** in Remote actions also lets you prepare a draft first and send it to the field focused when you tap **Send**.

## Settings

- **Pointer Smoothing** in the Mac menu offers **Balanced** for a steadier resting aim and **Classic** for the 1.2.0 filter settings.
- The Mac menu shows the connection status and lets you quit. The notch panel shows the watch model, battery, and pointer activity.
- To keep WatchPointer visible for longer, adjust **Display & Brightness › Wake Duration** and **General › Return to Clock › WatchPointer** on the watch.

<details>
<summary>Run and tune the Mac receiver from Terminal</summary>

Quit the menu bar receiver before starting a second instance. From the repository root, run the following commands in Terminal. Allow Bluetooth and Accessibility for Terminal when required.

```bash
cd Mac
swift run WatchPointer                  # default settings
swift run WatchPointer 1.2              # higher speed requires less rotation to reach an edge
swift run WatchPointer steady=0.6       # still-hand filter cutoff (Balanced: 0.56)
swift run WatchPointer quick=0.02       # less delay on fast movements (Balanced: 0.0135)
```

</details>

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| The watch shows movement but the Mac cursor stays still | Enable WatchPointer in **System Settings › Privacy & Security › Accessibility**, then reopen the receiver if macOS asks. |
| The cursor works but a swipe asks you to confirm Bluetooth pairing | Open **Pair Watch Input** on both devices, enter the Mac code on the watch, and confirm the system Bluetooth prompt. |
| A two-finger swipe switches browser tabs | Place both fingers on the pad before moving them together. |
| A horizontal two-finger swipe leaves the same Space open | Check that there is a neighboring desktop or full-screen app in Mission Control and that **Control + ← / →** switches Spaces on the Mac. |
| Dictation stays on the watch | Click the intended Mac field before tapping the microphone and keep it focused. See [Dictation](#dictation) for draft recovery. |

<details>
<summary>Build a matched pair if system Bluetooth pairing repeatedly fails</summary>

Create `.local/watch-signing.xcconfig` with your own team ID and bundle identifier.

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
PRODUCT_BUNDLE_IDENTIFIER = com.example.watchpointer
```

With your Apple Development signing identity available in Xcode, run `./build-local-input.sh .local/my-pair` from the repository root. Install both signed apps from that output and use **Pair Watch Input**. Keep the locally provisioned apps and their shared key private.

</details>

## Sky Shot

Open `Game/index.html` in a browser, press **F** for full screen, and tap the watch to start. Aim at paper planes as the sky turns from morning to sunset. Bullseyes count double and gold planes count triple.

## How it works

- **Watch** reads gravity and gyroscope samples 100 times a second. Gravity stabilizes vertical aim, and the gyroscope tracks horizontal turns. Each sample includes a watch timestamp.
- **Mac** projects the aim onto the display and smooths it with a [1€ filter](https://gery.casiez.net/1euro/). The cursor loop runs at up to 240 updates per second. Clicks use the aim at touch-down to reduce movement from the tap itself.
- **Bluetooth** carries pointer and remote input commands. See the protocol in [Receiver.swift](Mac/Sources/WatchPointer/Receiver.swift). The standard build protects remote input with Bluetooth encryption. Locally provisioned pairs use authenticated encryption in the app. Both require the six-digit pairing code for remote input.

Pointer packets use a separate path. A nearby Bluetooth device that speaks that protocol could move the cursor while the receiver is running. Quit the receiver when you finish using it. [Report a security issue](SECURITY.md)

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md) for test commands and bug reports. WatchPointer is available under the [MIT License](LICENSE). The original pointer project was created by Umar Afzal. [Original WatchPointer project](https://github.com/umarz317/WatchPointer)
