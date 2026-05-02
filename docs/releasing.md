# Releasing OpenMUX

OpenMUX has a native macOS-style release flow built around a committed product version, agent-authored changelog entries, generated GitHub Releases, and downloadable archives.

## Version and changelog model

OpenMUX uses a single product version:

- `VERSION` contains the current semantic version without a leading `v`
- `CHANGELOG.md` contains committed release notes
- Git tags use `v<version>`, such as `v0.1.0`
- `CFBundleShortVersionString` receives the release semver
- `CFBundleVersion` receives the build number from `BUNDLE_VERSION`, `BUILD_NUMBER`, or CI

Before tagging a release, inspect changes since the latest release:

```bash
Scripts/check-changes-since-release.sh
```

Then prepare the reviewed changelog and version update:

```bash
Scripts/prepare-release.sh 0.2.0 <<'EOF'
### Added

- Added ...
EOF
```

Agents can use the `create-release-notes` skill to analyze changes since the latest `v*` tag, recommend the semver bump, draft the changelog body, and ask before writing `VERSION` and `CHANGELOG.md`.

## Local packaging

Build release artifacts locally with:

```bash
make package-release
```

By default, local packaging reads the version from `VERSION`. You can override it for one-off checks:

```bash
make package-release RELEASE_VERSION=0.1.0
```

That command writes artifacts to `dist/release/`:

- `OpenMUX-<version>-macos-unsigned.zip`
- `omux-<version>-macos.tar.gz`
- `checksums.txt`

The app archive is produced from the existing unsigned app bundle flow in `Scripts/publish-unsigned.sh`. That flow ad-hoc signs the assembled app bundle so macOS sees a structurally valid bundle, but it does not use a Developer ID certificate or notarization. The CLI archive packages the release-built `omux` binary, SwiftPM resource bundles needed by CLI commands such as `omux theme`, and the repository license.

The app bundle also includes a bundled CLI binary at `OpenMUX.app/Contents/MacOS/omux`, so users who install only the app can:

- choose **OpenMUX → Install omux CLI** inside the app for the one-click install flow
- or link it from Terminal with:

```bash
/Applications/OpenMUX.app/Contents/MacOS/omux install-cli
```

By default that command installs `omux` into the first preferred directory already on `PATH`, or falls back to `~/.local/bin/omux` and prints the shell export line to add.

## GitHub Release flow

Pushing a version tag triggers [`.github/workflows/release.yml`](../.github/workflows/release.yml):

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow:

1. builds the vendored Ghostty runtime
2. verifies the repository
3. runs `make package-release RELEASE_VERSION=<tag-version>`
4. publishes a GitHub Release with the packaged artifacts attached
5. lets GitHub generate release notes automatically

Generated release notes are configured through [`.github/release.yml`](../.github/release.yml). `CHANGELOG.md` remains the committed release-note source of truth; GitHub's generated notes are useful as supplemental release-page context.

## Current distribution status

The current GitHub Release automation publishes **unsigned** macOS artifacts. The app bundle is ad-hoc signed for bundle integrity only, which is useful for early testers and internal dogfooding, but a public macOS release should move to:

1. Developer ID signing
2. notarized `.dmg` distribution
3. Homebrew cask publishing for the app
4. Homebrew formula or bottle publishing for `omux`

## Next step for public macOS installs

When Apple signing credentials are available, upgrade the release flow by:

1. signing the generated `.app` with a Developer ID Application certificate
2. building a distributable `.dmg`
3. notarizing and stapling the `.dmg`
4. attaching the notarized `.dmg` to the GitHub Release instead of, or alongside, the unsigned zip

That keeps the current tag/release/changelog flow intact while replacing the unsigned artifact with a Gatekeeper-friendly download.
