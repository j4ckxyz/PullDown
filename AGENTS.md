# PullDown contributor instructions

## Releases and versioning

- PullDown uses stable Semantic Versioning in `X.Y.Z` form. The source of truth is `VERSION`.
- Keep `MARKETING_VERSION` in `project.yml` identical to `VERSION`. Run `Scripts/validate-version.sh` before every build or pull request.
- Increment the version before every merge to `main`. Use a patch bump for compatible fixes, a minor bump for compatible features, and a major bump for breaking changes. Never reuse or decrease a published version.
- `CFBundleVersion` is the monotonically increasing GitHub Actions run number. Do not replace it with the marketing version or manually decrease it. Sparkle uses this build number to order updates.
- A push to `main` publishes GitHub Release `vX.Y.Z`. If that tag already exists, the workflow must fail instead of overwriting the release.

## Auto-update contract

- Sparkle is the updater. Preserve `UpdaterManager`, its early start in `AppDelegate`, and the standard Sparkle update UI unless a deliberate migration is agreed.
- The stable feed URL is `https://github.com/j4ckxyz/PullDown/releases/latest/download/appcast.xml`.
- Release archives and the appcast must be signed with the same Sparkle EdDSA key. The public key belongs in `project.yml`; the private key belongs only in the `SPARKLE_PRIVATE_KEY` GitHub Actions secret and the maintainer's Keychain. Never commit or print the private key.
- The release workflow creates separate Apple Silicon and Intel downloads plus a universal archive used by Sparkle. Do not point the appcast at a single-architecture archive.
- Keep automatic checks enabled and silent installation disabled. Users must retain the native choices to install, postpone, or skip a version.
- When changing the updater, test a real upgrade between two signed Release builds copied into `/Applications`; a Debug build intentionally does not contact the production feed.

## Project maintenance

- `project.yml` is the Xcode project source. Run `xcodegen generate` after changing it or adding source files, and commit the regenerated `PullDown.xcodeproj`.
- Run `swift test` and a Release build before publishing. Verify both architectures in GitHub Actions.
- Keep macOS 15 as the deployment floor and guard newer visual APIs with availability checks.
- Do not commit build products, DerivedData, exported signing keys, or downloaded tools.
