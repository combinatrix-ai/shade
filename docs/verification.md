# Local acceptance, 2026-09-09

- Swift core tests: 4 passed; timer boundary, explicit rearm, off-state, both-Shift hold and release behavior.
- Release app: built; property list and ad-hoc code signature validated.
- Native settings and menu panel: inspected with Computer Use; custom key recording and persisted settings verified after restart.
- One-minute countdown: observed reaching the dark state automatically.
- Physical display control: System Settings reported brightness changing from approximately 0.628 to 0. The screen remained readable to Computer Use.
- Normal UI interaction while dark: another app could be opened and clicked; brightness remained zero.
- Restore button: brightness returned to the exact saved value; auto-brightness returned to its prior enabled state. Wake prevention remained active.
- Crash recovery: killed only the Shade parent during a dark session. The restore guard restored brightness to the saved value; the parent's wake assertions were lifetime-bound.
- Input Monitoring: explicitly approved by the user, enabled through macOS UI and authentication, and app restarted. The default Shift event tap started successfully.

## Remaining physical acceptance

The user's physical both-Shift hold and custom shortcut activation have not yet been confirmed. Computer Use's app-directed synthesized custom keystroke did not activate the global Carbon hot key; this does not establish whether a physical keystroke works. Unit tests cover the hold state machine, not physical delivery. Login-item launch, lid transitions, and other hardware are not claimed as tested.
