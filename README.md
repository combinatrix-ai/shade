# Shade

A small macOS menu bar app that keeps the Mac awake while dimming only the built-in display. The desktop remains available to Computer Use.

## Behavior

- Starts off. Turn it on from the menu bar panel.
- After 1 minute (configurable: 30 seconds, 1, 3, or 5 minutes), sets the built-in display's brightness to zero.
- Hold **both Shift keys for one second** to restore the saved brightness. Keeping the Mac awake continues.
- Perform the same action while the display is visible to schedule dimming again. Ordinary typing and pointer movement do not restore the brightness.
- Alternatively record a custom global shortcut with Command, Control, or Option.
- Turning off or quitting restores the brightness and releases this app's wake assertions. Sessions end after a maximum of 8 hours. Manual sleep or switching away from the user session ends the session.
- Screen-lock preferences are never changed. An already locked Mac is not unlocked.

## Build and run

Requires macOS 14+, Xcode command-line tools, and Swift 6. No third-party dependencies.

```sh
./scripts/check.sh
open build/Shade.app
```

`./scripts/build.sh` creates an ad-hoc signed local app. Set `SHADE_SIGN_IDENTITY` or the gitignored `.signing-identity` file to a signing identity to use your own certificate. This is a local developer build, not a notarized release or an App Store submission.

For the both-Shift gesture, enable Shade under **System Settings > Privacy & Security > Input Monitoring**, then click **Recheck** in Shade's settings. macOS may require a restart after permission changes. Custom shortcuts use Carbon's hot-key registration and do not need Input Monitoring. Shade does not record or transmit keyboard events.

The default setting opens the app with wake prevention off. Login launch is opt-in. The menu panel can also be opened from settings or by reopening Shade.

```sh
open build/Shade.app --args --demo
```

Demo mode previews the native interface without controlling brightness or power. The accepted interactive design is in [docs/mock.html](docs/mock.html).

## Recovery and boundaries

The original brightness is read immediately before each dim. Before setting it to zero, Shade starts a companion process and waits for it to confirm that it can load the brightness API. When Shade exits or crashes, the pipe closes and the companion restores the original value. A failed restoration can also be recovered with the Mac's brightness keys.

Display control uses the private macOS `DisplayServices` framework because macOS does not expose a suitable public built-in brightness API. Availability is checked at runtime and dimming fails closed if unavailable. Future OS updates can require maintenance. No screen overlay, simulated user input, display disconnect, screenshot, or persistent lock-setting change is used.

Dimming is not a security boundary; anyone can restore the display. Only the built-in display is supported. Lid-closed operation and external displays are outside the scope of this version. Automatic brightness behavior and sleep overrides may vary with hardware or managed-device policy; verify on the target Mac.

## Verification

`swift test` covers timer boundaries, explicit rearming after restore, off-state behavior, interrupted Shift holds, and one-shot hold detection. `./scripts/build.sh` compiles the full app. Live acceptance should additionally check timer-driven dimming, normal input staying dark, global shortcut restoration, normal quit, and crash restoration. Do not infer live acceptance from a successful build.

See [docs/verification.md](docs/verification.md) for the measured local results and remaining physical checks. Ad-hoc signing may require granting Input Monitoring again after a code change; use a stable signing certificate for ongoing distribution.
