# Auto-lock status

The ON/OFF badge describes Shade's intent. The adjacent line describes automatic locking, independently of Shade's dimming timer. Manual locking is always possible.

- **Auto-Lock after X min**: configured inactivity interval, not time remaining. For confirmed, unblocked routes, use the earlier of display sleep and screen saver activation, then add the password grace period. Disabled routes do not participate. Preserve seconds instead of rounding up.
- **Auto-Lock Prevented**: the relevant routes currently have recognized prevention assertions. When Shade is off, add **By another app**. This describes the current hold, not a permanent guarantee.
- **Auto-Lock Disabled**: password protection is explicitly off, or both automatic routes are explicitly disabled.
- **Normal Auto-Lock**: a required setting or suppression state cannot be determined. Missing values are never treated as disabled.

## Read-only implementation

`AutoLockMonitor` runs on a utility queue, refreshing about every five seconds and invalidating on Shade toggles, power changes, and panel opening. A generation check prevents an old asynchronous read from restoring stale state. Demo mode uses deterministic values and never reads machine state.

- Power source: IOKit power-source API. Display timer: the matching AC or battery profile in `/Library/Preferences/com.apple.PowerManagement.plist`. Unsupported/missing profiles fall back to unknown.
- Screen saver: effective `com.apple.screensaver` `idleTime` through `CFPreferencesCopyAppValue`, including managed preferences. Zero means disabled; absent or malformed values mean unknown.
- Password grace: bounded, status-only `/usr/sbin/sysadminctl -screenLock status`; this resolves settings that are absent from ordinary defaults. Unrecognized output fails closed to unknown. No authentication or settings writes.
- Holds: `IOPMCopyAssertionsByProcess`, checking `kIOPMAssertionLevelOn` (255). A system-sleep assertion alone is not display/lock prevention. Ordinary WindowServer activity is not an application hold. Recognize the explicit sustained `caffeinate -u` assertion used by Shade; display-only holds and unrecognized application activity do not establish screen saver behavior, so that route remains unknown. This deliberately does not claim to recognize every third-party lock-prevention mechanism.

The model covers idle display and screen saver routes, not manual lock, lid close, administrative lock commands, arbitrary third-party security agents, or overriding hardware/system conditions. Assertion presence is not an end-to-end guarantee that macOS will never lock. No setting or process is modified to measure this status.

## Verification

`./scripts/check.sh` runs policy/parser/assertion tests, existing regressions, release build and signature verification, and the non-dimming restore-guard test. A read-only diagnostic is available without starting the app UI or wake assertions:

```sh
build/Shade.app/Contents/MacOS/Shade --lock-status
```

Tests cover the earlier route plus grace, disabled and missing routes, partial prevention, real IOKit assertion levels, unrelated system-sleep holds, ordinary user input, malformed values, unsupported command output, and deterministic demo transitions. A local macOS 26.6 read was cross-checked with both Lock Screen and Wallpaper → Screen Saver settings. No physical idle-to-lock transition was forced during verification.

API references: [display-sleep assertions](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridledisplaysleep), [screen saver settings](https://developer.apple.com/documentation/devicemanagement/screensaver), and the installed IOKit SDK headers. `sysadminctl` status output was checked against the installed tool's supported strings.
