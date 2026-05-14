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
- `openmux-install.sh`
- `checksums.txt`

The app archive is produced from the existing unsigned app bundle flow in `Scripts/publish-unsigned.sh`. That flow ad-hoc signs the assembled app bundle so macOS sees a structurally valid bundle, but it does not use a Developer ID certificate or notarization. The CLI archive packages the release-built `omux` binary, SwiftPM resource bundles needed by CLI commands such as `omux theme`, the release `VERSION`, and the repository license. The app bundle also includes `Contents/Resources/VERSION` so bundled tools can report their installed version offline.

`checksums.txt` includes SHA-256 entries for the app archive, CLI archive, and release installer script. `omux update` depends on the predictable app archive name and checksum entry to verify the downloaded app before it unarchives or installs anything.

The app bundle also includes a bundled CLI binary at `OpenMUX.app/Contents/MacOS/omux`, so users who install only the app can:

- choose **OpenMUX → Install omux CLI** inside the app for the one-click install flow
- or link it from Terminal with:

```bash
/Applications/OpenMUX.app/Contents/MacOS/omux install-cli
```

By default that command installs `omux` into the first preferred directory already on `PATH`, or falls back to `~/.local/bin/omux` and prints the shell export line to add.

For direct-download installs outside Finder, the release also includes `openmux-install.sh`, intended for repo/website `curl | bash` use:

```bash
curl -fsSL https://github.com/finger-gun/omux/releases/latest/download/openmux-install.sh | bash
```

That bootstrap installer is version-pinned to the release it ships with, downloads the matching app archive plus `checksums.txt`, verifies the checksum, validates `OpenMUX.app`, and installs into `/Applications/OpenMUX.app` when writable or `~/Applications/OpenMUX.app` otherwise. It can optionally run `--install-cli` after installing the app. Like `omux update`, it does not attempt hidden privilege escalation.

Users can inspect and update installed releases with:

```bash
omux version
omux update
```

`omux update` reads the latest GitHub Release metadata, downloads `OpenMUX-<version>-macos-unsigned.zip` plus `checksums.txt`, verifies the app archive checksum, stages the app under the user's temporary directory, validates `OpenMUX.app`, and installs it into the current app location when writable. If OpenMUX is running, it prompts before closing the app and hands off the final copy to a detached helper outside the app bundle being replaced. If `/Applications` is not writable and no current app target is available, it uses `~/Applications/OpenMUX.app` without invoking hidden privilege escalation.

## GitHub Release flow

Create and push the version tag with:

```bash
make tag-release
```

The command reads `VERSION`, verifies that `CHANGELOG.md` contains notes for that version, refuses to tag a dirty working tree, then runs the equivalent of `git tag v<version>` and `git push origin v<version>`.

Pushing the version tag triggers [`.github/workflows/release.yml`](../.github/workflows/release.yml).

The workflow:

1. builds the vendored Ghostty runtime
2. verifies the repository
3. runs `make package-release RELEASE_VERSION=<tag-version>`
4. launches the packaged app from the generated release archive
5. runs the packaged release installer smoke test
6. extracts the matching section from `CHANGELOG.md`
7. publishes a GitHub Release with the packaged artifacts attached and the committed changelog notes as the release body

`CHANGELOG.md` is the committed release-note source of truth. The GitHub Release body is generated from the matching `## <version>` section at the tagged commit.

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
