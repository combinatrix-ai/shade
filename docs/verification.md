# Local acceptance, 2026-09-09

- Swift core tests: 4 passed; timer boundary, explicit rearm, off-state, both-Shift hold and release behavior.
- Release app: built; property list and initial ad-hoc code signature validated. The final local build uses an existing development certificate, configured only in a gitignored file.
- Native settings and menu panel: inspected with Computer Use; custom key recording and persisted settings verified after restart.
- One-minute countdown: observed reaching the dark state automatically.
- Physical display control: System Settings reported brightness changing from approximately 0.628 to 0. The screen remained readable to Computer Use.
- Normal UI interaction while dark: another app could be opened and clicked; brightness remained zero.
- Restore button: brightness returned to the exact saved value; auto-brightness returned to its prior enabled state. Wake prevention remained active.
- Crash recovery: killed only the Shade parent during a dark session. The restore guard restored brightness to the saved value; the parent's wake assertions were lifetime-bound.
- Input Monitoring: explicitly approved by the user and worked in the initial ad-hoc build after authentication and restart. A later rebuild invalidated that grant. The final build uses a stable development certificate, but macOS is still holding the old permission registration; replacing that registration is awaiting OS authentication. Do not treat the final build as having a working Shift event tap yet.

## Remaining physical acceptance

The user's physical both-Shift hold and custom shortcut activation have not yet been confirmed. Computer Use's app-directed synthesized custom keystroke did not activate the global Carbon hot key; this does not establish whether a physical keystroke works. Unit tests cover the hold state machine, not physical delivery. Login-item launch, lid transitions, and other hardware are not claimed as tested.
