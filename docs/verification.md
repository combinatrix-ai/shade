# Local acceptance, 2026-09-09

- Swift core tests: 4 passed; timer boundary, explicit rearm, off-state, both-Shift hold and release behavior.
- Release app: built; property list and initial ad-hoc code signature validated. The final local build uses an existing development certificate, configured only in a gitignored file.
- Native settings and menu panel: inspected with Computer Use; custom key recording and persisted settings verified after restart.
- One-minute countdown: observed reaching the dark state automatically.
- Physical display control: System Settings reported brightness changing from approximately 0.628 to 0. The screen remained readable to Computer Use.
- Normal UI interaction while dark: another app could be opened and clicked; brightness remained zero.
- Restore button: brightness returned to the exact saved value; auto-brightness returned to its prior enabled state. Wake prevention remained active.
- Crash recovery: killed only the Shade parent during a dark session. The restore guard restored brightness to the saved value; the parent's wake assertions were lifetime-bound.
- Input Monitoring: explicitly approved by the user and worked in the initial ad-hoc build after authentication and restart. A later rebuild invalidated that grant. The final build uses a stable development certificate. Removing only the old Shade registration, re-adding the signed app through the macOS file picker, and restarting resolved the stale grant. The final build now starts its Shift event tap without a permission error. Physical hold activation is still awaiting confirmation.

## Remaining physical acceptance

The user's physical both-Shift hold and custom shortcut activation have not yet been confirmed. Computer Use's app-directed synthesized custom keystroke did not activate the global Carbon hot key; this does not establish whether a physical keystroke works. Unit tests cover the hold state machine, not physical delivery. Login-item launch, lid transitions, and other hardware are not claimed as tested.

## Recorder and freeze fix (2026-09-09, follow-up)

- Replaced the Shift/custom mode selector with one recorder field. The default is Control+Option+Command+D; no Input Monitoring APIs remain in the app.
- A sample of the unresponsive process located its main thread in `AppModel.restore -> RestoreGuard.finish -> Process.waitUntilExit`. The user-requested frozen process was killed before editing.
- Normal restore now sends an explicit disarm byte and never waits for child termination on the UI thread. Startup acknowledgment has a three-second timeout. The child still restores brightness on parent pipe EOF.
- `scripts/check.sh` passes two session tests and 20 real child disarm/exit cycles without changing the display. The removed Shift tests are no longer applicable.
- Live UI: default shortcut registered, recorder opened and canceled; two dim/restore cycles completed without blocking and the app could be turned off afterward.
- The panel now hides on outside mouse events, application deactivation, and key-window resignation. Escape is handled by the local key monitor and panel cancel action. CUA's app-directed Escape did not yield an observable dismissal, so physical outside-click/Escape acceptance remains to be confirmed rather than inferred from code.
