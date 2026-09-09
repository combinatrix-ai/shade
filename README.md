# Shade

**A band-aid for the Computer Use era. Darken the screen while the agent keeps working.**

Shade is a small macOS menu bar app that keeps the Mac awake while dimming its built-in display to zero. The desktop stays available to Computer Use, without leaving the screen lit throughout an unattended agent session. Think of it as an Amphetamine-like utility for a Mac that an agent is still using after its human has stepped away.

## Why a band-aid?

When you step away from your Mac, you do not want its screen exposing your work to anyone nearby. Normally, you would lock it. But locking the desktop also prevents Computer Use from continuing its work. Shade is a stopgap: leave the session unlocked so the agent can work, and darken the physical display so its contents are not left in plain sight.

**Do not use Shade for serious security needs. A dark screen is still an unlocked Mac.** Anyone with physical access can turn the brightness back up and use the session. Shade does not provide access control or replace a screen lock. If an unattended, unlocked session is unacceptable for your data or environment, lock the Mac and stop Computer Use instead.

We expect this kind of separation between an agent's working session and the physical display to become an OS-level concern. Our hope is that macOS will eventually provide a native solution. Shade is the band-aid for the meantime: a small, reversible utility, deliberately limited to keeping the session awake, dimming the screen, and restoring its brightness.

**Shade is intended to become unnecessary.** If macOS provides a reliable native way to do this, retiring Shade would be a good outcome.

## Behavior

- Starts off. Double-click or right-click the menu bar icon to toggle wake prevention. A single click opens the panel after the system double-click interval.
- After 1 minute (configurable: 30 seconds, 1, 3, or 5 minutes), sets the built-in display's brightness to zero.
- Press **Control + Option + Command + D** to restore the saved brightness. Keeping the Mac awake continues.
- Perform the same action while the display is visible to schedule dimming again. Ordinary typing and pointer movement do not restore the brightness.
- Click the shortcut field and press a new combination with Command, Control, or Option to replace it. Escape cancels recording.
- The menu panel closes on an outside click, app switch, or Escape.
- Turning off or quitting restores the brightness and releases this app's wake assertions. Sessions end after a maximum of 8 hours. Manual sleep or switching away from the user session ends the session.
- Screen-lock preferences are never changed. An already locked Mac is not unlocked.

## Build and run

Requires macOS 14+, Xcode command-line tools, and Swift 6. No third-party dependencies.

```sh
./scripts/check.sh
open build/Shade.app
```

`./scripts/build.sh` creates an ad-hoc signed local app. Set `SHADE_SIGN_IDENTITY` or the gitignored `.signing-identity` file to a signing identity to use your own certificate. This is a local developer build, not a notarized release or an App Store submission.

Shortcuts use Carbon hot-key registration and do not need Input Monitoring. Shade does not record or transmit keyboard events. If another app already owns a combination, Shade reports registration failure and does not dim.

The default setting opens the app with wake prevention off. Login launch is opt-in. The menu panel can also be opened from settings or by reopening Shade.

```sh
open build/Shade.app --args --demo
```

Demo mode previews the native interface without controlling brightness or power. The accepted interactive design is in [docs/mock.html](docs/mock.html).

## Recovery and boundaries

The original brightness is read immediately before each dim. Before setting it to zero, Shade starts a companion process and waits for it to confirm that it can load the brightness API. On a crash, the pipe closes and the companion restores the original value. On normal restoration, the parent restores brightness and sends an explicit disarm message; the UI never waits for child exit. A failed restoration can also be recovered with the Mac's brightness keys.

Display control uses the private macOS `DisplayServices` framework because macOS does not expose a suitable public built-in brightness API. Availability is checked at runtime and dimming fails closed if unavailable. Future OS updates can require maintenance. No screen overlay, simulated user input, display disconnect, screenshot, or persistent lock-setting change is used.

Dimming is not a security boundary; anyone can restore the display. Only the built-in display is supported. Lid-closed operation and external displays are outside the scope of this version. Automatic brightness behavior and sleep overrides may vary with hardware or managed-device policy; verify on the target Mac.

## Verification

`swift test` covers timer boundaries, explicit rearming after restore, off-state behavior, explicit timer rescheduling. `./scripts/build.sh` compiles the full app. Live acceptance should additionally check timer-driven dimming, normal input staying dark, global shortcut restoration, normal quit, and crash restoration. Do not infer live acceptance from a successful build.

See [docs/verification.md](docs/verification.md) for the measured local results and remaining physical checks. Use a stable signing certificate for ongoing distribution.

The original mock in `docs/mock.html` is historical: the keyboard selector was subsequently replaced with a single recorder field. `scripts/test-restore-guard.py` runs 20 real companion-process disarm cycles without changing the display.
