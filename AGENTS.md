# Shade
Native macOS menu bar utility. Keep system settings unchanged; only hold temporary assertions and dim the built-in display. Always prepare crash restoration before dimming. Never dim without a working recovery shortcut.

- `./scripts/check.sh`: core tests and release app build.
- `./scripts/build.sh`: creates `build/Shade.app` (ignored).
- `open build/Shade.app --args --demo`: harmless UI preview, no display or power changes.
- Runtime screen/permission tests require a real unlocked Mac. Report these separately from unit tests.
- Preserve the accepted UI in `docs/mock.html`.
- Do not store raw keyboard events, credentials, personal information, or build products.
