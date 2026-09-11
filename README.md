# Shade

**A band-aid for the Computer Use era. Darken the screen while the agent keeps working.**

Shade is a small macOS menu bar app that keeps the Mac awake while dimming its built-in display to zero. The desktop stays available to Computer Use, without leaving the screen lit throughout an unattended agent session. Think of it as an Amphetamine-like utility for a Mac that an agent is still using after its human has stepped away.

## Why a band-aid?

When you step away from your Mac, you do not want its screen exposing your work to anyone nearby. Normally, you would lock it. But locking the desktop also prevents Computer Use from continuing its work. Shade is a stopgap: leave the session unlocked so the agent can work, and darken the physical display so its contents are not left in plain sight.

**Do not use Shade for serious security needs. A dark screen is still an unlocked Mac.** Anyone with physical access can turn the brightness back up and use the session. Shade does not provide access control or replace a screen lock. If an unattended, unlocked session is unacceptable for your data or environment, lock the Mac and stop Computer Use instead.

We expect this kind of separation between an agent's working session and the physical display to become an OS-level concern. Our hope is that macOS will eventually provide a native solution. Shade is the band-aid for the meantime: a small, reversible utility, deliberately limited to keeping the session awake, dimming the screen, and restoring its brightness.

**Shade is intended to become unnecessary.** If macOS provides a reliable native way to do this, retiring Shade would be a good outcome.

## Behavior

- **Only on power adapter** defaults on. Unplugging restores brightness and pauses Shade, releasing its sleep-prevention assertions. Reconnecting resumes the session with a fresh dimming countdown. Turning Shade off while paused cancels automatic resume. Sleep, switching user sessions, or quitting also cancels it. Turn this setting off to use Shade on battery.
- Starts off. Double-click or right-click the menu bar icon to toggle wake prevention. A single click opens the panel after the system double-click interval.
- After 1 minute without hardware input (configurable: 1–60 minutes, in whole minutes), sets the built-in display's brightness to zero. Physical keyboard and pointer activity postpone dimming while the display is visible.
- Click **Dimming in m:ss** to choose a delay using the slider, minute field, or presets. **Set timer** restarts the countdown from that moment and saves the delay for future sessions; **Cancel** or Escape discards the edit. The same control is available under **Settings → Dim after**.
- Press **Control + Option + Command + D** to restore the saved brightness. Keeping the Mac awake continues.
- Restoring the display automatically starts a fresh dimming countdown. The shortcut restarts that countdown while visible. The brightness-up key also returns to automatic dimming, preserving the brightness you chose. With **Wake on touch** enabled, physical trackpad movement, mouse activity, or typing restores the display and starts a fresh countdown. It defaults off; resting a finger without generating input is not detected.
- Click the shortcut field and press a new combination with Command, Control, or Option to replace it. Escape cancels recording.
- The menu panel closes on an outside click or app switch. Escape cancels an open timer edit first; otherwise it closes the panel.
- Turning off or quitting restores the brightness and releases this app's wake assertions. Sessions end after a maximum of 8 hours. Manual sleep or switching away from the user session ends the session.
- Screen-lock preferences are never changed. An already locked Mac is not unlocked.

## Install and update

Download [Shade.dmg](https://github.com/combinatrix-ai/shade/releases/latest/download/Shade.dmg), drag Shade into Applications, and open it. Requires Apple Silicon and macOS 14 or later. The tutorial explains recovery; Shade starts off. Check “Don’t show on startup” to dismiss the tutorial on future launches.

Releases use Developer ID signing and notarization. Sparkle checks for updates; use Settings → Check for Updates… for a manual check. See [release requirements](docs/releasing.md). The first public version has no prior public version for an upgrade E2E; verify version-to-version replacement at the next release.

Preferences stay in macOS UserDefaults under `ai.combinatrix.shade`. Shade reads elapsed hardware idle time, not input contents. Update checks contact GitHub. See [privacy](https://shade.combinatrix.ai/privacy.html) and [support](https://github.com/combinatrix-ai/shade/issues).

## Build and run

Requires macOS 14+, Xcode command-line tools, and Swift 6. Sparkle is pinned through Swift Package Manager for signed updates.

```sh
./scripts/check.sh
open build/Shade.app
```

`./scripts/build.sh` creates an ad-hoc signed local app. Set `SHADE_SIGN_IDENTITY` or the gitignored `.signing-identity` file to a signing identity to use your own certificate. This is a local developer build, not a notarized release or an App Store submission.

Shortcuts use Carbon hot-key registration and do not need Input Monitoring. Shade does not record or transmit keyboard events. If another app already owns a combination, Shade reports registration failure and does not dim.

The default setting opens the app with wake prevention off. Login launch is opt-in. Settings and the tutorial open inside the same menu panel. Reopen Shade or single-click the status icon to show it.

```sh
open build/Shade.app --args --demo
```

Demo mode previews the native interface without controlling brightness or power. The accepted interactive design is in [docs/mock.html](docs/mock.html).

## Recovery and boundaries

The original brightness is read immediately before each dim. Before setting it to zero, Shade starts a companion process and waits for it to confirm that it can load the brightness API. On a crash, the pipe closes and the companion restores the original value. On normal restoration, the parent restores brightness and sends an explicit disarm message; the UI never waits for child exit. A failed restoration can also be recovered with the Mac's brightness keys.

Display control uses the private macOS `DisplayServices` framework because macOS does not expose a suitable public built-in brightness API. Availability is checked at runtime and dimming fails closed if unavailable. Future OS updates can require maintenance. No screen overlay, simulated user input, display disconnect, screenshot, or persistent lock-setting change is used.

Dimming is not a security boundary; anyone can restore the display. Only the built-in display is supported. Lid-closed operation and external displays are outside the scope of this version. Automatic brightness behavior and sleep overrides may vary with hardware or managed-device policy; verify on the target Mac.

## Verification

`swift test` covers timer boundaries, automatic rearming after restore, off-state behavior, explicit timer rescheduling. `./scripts/build.sh` compiles the full app. Live acceptance should additionally check timer-driven dimming, normal input staying dark, global shortcut restoration, normal quit, and crash restoration. Do not infer live acceptance from a successful build.

See [docs/verification.md](docs/verification.md) for the measured local results and remaining physical checks. Use a stable signing certificate for ongoing distribution.

The accepted UI mock is preserved in `docs/mock.html`. `scripts/test-restore-guard.py` runs 20 real companion-process disarm cycles without changing the display.

Hardware activity is read from IOHIDSystem’s `HIDIdleTime`; no key contents or pointer coordinates are collected and no Input Monitoring permission is required. In local measurement, Computer Use clicks did not reset this counter. This is a best-effort distinction, not a guarantee for every automation tool or virtual HID driver. If the counter cannot be read, Shade stops and restores the display.
