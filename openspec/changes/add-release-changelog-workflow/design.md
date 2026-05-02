## Context

OpenMUX currently packages releases by deriving a version from a pushed `v*` tag in GitHub Actions or by requiring `RELEASE_VERSION` locally. The packaging scripts already write the native macOS bundle fields correctly: `SHORT_VERSION` becomes `CFBundleShortVersionString`, and `BUNDLE_VERSION` becomes `CFBundleVersion`. What is missing is an inspectable product version, a committed changelog, and a project-specific agent workflow that can turn repository history into release notes.

This change keeps the release process terminal-driven and native to a Swift/macOS app. It borrows the useful part of the SISU workflow--agent analysis of changes since the last release--without adopting npm package versioning or independent package releases.

## Goals / Non-Goals

**Goals:**

- Use a committed `VERSION` file as OpenMUX's single product semver source of truth.
- Use `CHANGELOG.md` as the committed release-note history.
- Add scripts that support local inspection and release preparation without requiring Node, npm, or a package registry.
- Add an OpenMUX-specific skill that guides agents to analyze changes since the latest release tag, recommend a semver bump, draft changelog entries, and ask for confirmation before writing.
- Keep existing tag-triggered GitHub Release packaging compatible.

**Non-Goals:**

- No npm package publishing, `package.json.version`, or Changesets dependency.
- No signing, notarization, DMG, cask, or formula publishing changes.
- No runtime feature work.
- No changes to keyboard/input handling, hooks contracts, plugin APIs, IPC contracts, or the libghostty bridge boundary.

## Decisions

1. **Use `VERSION` as the product version source of truth.**

   `VERSION` will contain a plain semantic version such as `0.2.0`, without a leading `v`. Local packaging will use it when `RELEASE_VERSION` is not provided. GitHub Actions will continue to derive the release version from the tag so the tagged artifact cannot accidentally package a different version.

   Alternative considered: use `package.json.version`. This was rejected because OpenMUX is a Swift/macOS app, not an npm package, and Apple bundle metadata should remain the native product version surface.

2. **Keep Apple bundle versioning split.**

   `CFBundleShortVersionString` remains the user-visible semver. `CFBundleVersion` remains a monotonically increasing build number supplied by CI or `BUNDLE_VERSION`/`BUILD_NUMBER`.

   Alternative considered: encode prerelease metadata or build numbers in the marketing version. This was rejected to avoid surprising macOS tooling and keep bundle metadata simple.

3. **Use retrospective release analysis first.**

   The primary agent workflow will inspect `git log` and `git diff` since the latest `v*` tag, group changes by OpenMUX surface, infer semver impact, and draft a changelog section. Per-change note files can be added later if release volume demands more ceremony.

   Alternative considered: add `.changeset`-style pending notes immediately. This was rejected for now because a single-product early-stage app benefits from lower release overhead.

4. **Represent changed areas as OpenMUX surfaces.**

   The analysis script will group files into surfaces such as CLI, app shell, terminal bridge, config, hooks, themes, packaging, docs, OpenSpec, and vendored Ghostty. These groupings give the skill useful context while avoiding fake package boundaries.

   Alternative considered: report only raw files and commits. That is simpler but gives agents less structure for semver reasoning.

5. **Keep release preparation explicit and non-tagging.**

   A release preparation script will validate a target version, update `VERSION`, and prepend a changelog section. It will not create commits, tags, or push to remotes. This keeps state changes reviewable and avoids automation that can publish accidentally.

   Alternative considered: a one-shot script that updates files, commits, tags, and pushes. This was rejected because OpenMUX release automation is still early and should remain inspectable.

## Risks / Trade-offs

- **Risk: Agent-written changelogs can overstate user impact.** -> The skill must show its analysis, semver reasoning, and draft notes before writing files.
- **Risk: `VERSION` and Git tag can diverge.** -> CI continues to derive release artifacts from the tag; local scripts validate semver and docs make the expected flow explicit.
- **Risk: Surface grouping can miss new directories.** -> Unknown changed files are reported under `Other` so they remain visible.
- **Risk: No pending note files means old changes may be harder to interpret.** -> The analysis tool reports commits and files since tag; pending notes can be introduced later without changing the native version model.

## Migration Plan

1. Add initial `VERSION` and `CHANGELOG.md`.
2. Add release analysis and preparation scripts.
3. Update packaging defaults and release documentation.
4. Add the project skill for agent-authored release notes.
5. Validate local script behavior and existing release packaging.

Rollback is straightforward: remove the new scripts, skill, `VERSION`, and `CHANGELOG.md` usage, then restore `RELEASE_VERSION` as the required local packaging input.

## Open Questions

- Should a future change add pending `.openmux-changes/*.md` note files if the project grows beyond retrospective release analysis?
- Should prerelease tags such as `v0.2.0-beta.1` be supported by release preparation, or should they remain manual for now?
