## Why

OpenMUX needs a native macOS-style release workflow that preserves Apple bundle version conventions while giving maintainers the agent-authored changelog experience that works well in SISU. The current flow can package a tagged version, but release notes are generated externally and there is no committed source of truth for product version or changelog intent.

## Goals

- Make the OpenMUX product version explicit, inspectable, and consumable by local packaging and CI release flows.
- Add a low-ceremony release analysis workflow where an agent can inspect changes since the latest release tag, recommend the next semantic version, and draft a user-focused changelog.
- Keep macOS bundle metadata native: user-visible semver maps to `CFBundleShortVersionString`, while build metadata maps to `CFBundleVersion`.
- Preserve the existing terminal-first packaging flow and avoid adding unrelated background services or vendor-specific release infrastructure.

## Non-goals

- Do not introduce npm package publishing semantics or independent package versions.
- Do not replace Apple bundle versioning with `package.json.version`.
- Do not change signing, notarization, DMG generation, or Homebrew publishing in this change.
- Do not alter keyboard/input behavior, extension APIs, or the libghostty bridge boundary.

## What Changes

- Add a single-product release workflow centered on a committed `VERSION` file and `CHANGELOG.md`.
- Add project-local release tooling that:
  - finds the latest `v*` release tag,
  - reports changed OpenMUX surfaces since that tag,
  - validates semver/version inputs,
  - can prepare a release by updating `VERSION` and prepending a changelog section.
- Add an OpenMUX-specific release-note skill that asks an agent to analyze changes since the last release, recommend a semver bump, explain the reasoning, and ask before writing release files.
- Update local packaging and GitHub release documentation to consume `VERSION` by default while still allowing explicit `RELEASE_VERSION` overrides.
- Keep existing GitHub Release packaging compatible with tag-triggered releases.

## Capabilities

### New Capabilities

- `release-changelog-workflow`: Native OpenMUX release versioning, release analysis, and agent-authored changelog preparation.

### Modified Capabilities

None.

## Impact

- Affected files and systems:
  - `VERSION`
  - `CHANGELOG.md`
  - `.github/skills/*`
  - `Scripts/*`
  - `Makefile`
  - `.github/workflows/release.yml`
  - `docs/releasing.md`
  - `docs/development.md`
- The change is local tooling and documentation only. It does not affect runtime terminal behavior, keyboard/input correctness, libghostty integration, hooks payloads, plugin APIs, or control-plane contracts.
- The workflow aligns with OpenMUX principles by keeping release state inspectable, scriptable, terminal-driven, and independent of npm publishing or hosted release-note generation.
