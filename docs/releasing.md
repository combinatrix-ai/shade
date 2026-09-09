# Release contract

Shade is distributed directly for Apple Silicon Macs running macOS 14 or later. Intel and the Mac App Store are not supported by this release workflow.

The single version source is Info.plist: marketing version maps to `v<version>` and the build number increases on every release. Update payload names stay `Shade.zip` and `appcast.xml`; the installer is `Shade.dmg`.

## One-time configuration

Configure the GitHub `release` environment with these secrets (never commit their values):

- BUILD_CERTIFICATE_BASE64: Developer ID Application P12 archive
- P12_PASSWORD and KEYCHAIN_PASSWORD
- APPLE_ID, APPLE_TEAM_ID, NOTARY_PASSWORD
- SPARKLE_ED_PRIVATE_KEY: Sparkle EdDSA key

Set the environment variable SHADE_SIGN_IDENTITY to the Developer ID Application identity. Embed the matching public key in SUPublicEDKey and the stable public update URL in SUFeedURL. Keep the private key securely backed up; never regenerate it for an existing distribution.

## Each release

1. Run `./scripts/check.sh`, audit Git history with `gitleaks git --redact`, and inspect the diff for personal information.
2. Update both version fields and add `docs/releases/v<version>.md` with user-facing notes.
3. Verify CI on the exact main commit, credentials, signing identity, and public key. Create and push an annotated matching tag.
4. Wait for the Release workflow. It fails closed on signing, notarization, packaging, and signature verification failures. No unsigned fallback is published.
5. Download the public DMG and ZIP, verify SHA256SUMS, mount the DMG, extract the ZIP with `ditto -x -k`, and verify each app with `codesign --verify --deep --strict`, `xcrun stapler validate`, and `spctl --assess`.
6. Install outside the checkout. Verify first launch, dim/restore, auto dim, settings persistence, and the update check. Test actual old-to-new Sparkle replacement from the second release onward.

Local release uses the same `scripts/release.sh` with SHADE_SIGN_IDENTITY, NOTARY_PROFILE, SPARKLE_KEY_FILE, and RELEASE_REPO. All outputs are in ignored `dist/`. Never copy a development-signed build into a public release.

Sparkle shows update availability, progress, errors, and restart prompts through its standard UI. Demo mode does not initialize the updater and does not persist preferences or register login items.
