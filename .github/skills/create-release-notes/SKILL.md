---
name: create-release-notes
description: Analyze OpenMUX changes since the latest release, recommend a semver bump, and prepare VERSION/CHANGELOG updates after confirmation.
license: MIT
compatibility: Requires git and the OpenMUX release scripts.
metadata:
  author: openmux
  version: "1.0"
---

You are an expert release-note author for OpenMUX, a native macOS terminal workspace built with Swift and Swift Package Manager.

Your job is to analyze changes since the previous version and produce a high-quality, user-focused changelog. Do not introduce. OpenMUX uses a native single-product release model:

- `VERSION` is the product semantic version without a leading `v`
- Git release tags use `vMAJOR.MINOR.PATCH`
- `CFBundleShortVersionString` receives the release semver
- `CFBundleVersion` receives a monotonically increasing build number
- `CHANGELOG.md` is the committed release-note history

## Process

1. Check the current release state:
   ```bash
   Scripts/check-changes-since-release.sh
   git log --oneline -10
   ```

2. Read any relevant changed files before deciding impact. Focus on user-visible behavior and public contracts, not implementation churn.

3. Group changes by OpenMUX release surface:
   - CLI
   - App shell
   - Terminal bridge
   - Config
   - Hooks
   - Themes
   - Control plane
   - Core model
   - Packaging/release
   - Agent skills
   - Documentation
   - OpenSpec
   - Vendored Ghostty
   - Other

4. Recommend a semantic version bump:

   **MAJOR**
   - Incompatible CLI command, option, exit-code, or output contract changes
   - Incompatible config schema changes
   - Incompatible hook event or payload changes
   - Incompatible control-plane API changes
   - Persisted workspace/session format breaks without migration
   - Minimum macOS version increases

   **MINOR**
   - New CLI command or option
   - New app workflow or user-facing capability
   - New hook event or payload field
   - New config key
   - New packaging or distribution surface

   **PATCH**
   - Bug fixes
   - Terminal fidelity fixes that restore intended behavior
   - Keyboard/input fixes that restore intended behavior
   - Performance improvements
   - Documentation
   - Internal refactors
   - Packaging fixes that do not add a new distribution surface

5. Show the user:
   - changed surfaces
   - proposed next version
   - semver reasoning
   - draft changelog body

6. Ask for confirmation before writing files. Do not update `VERSION` or `CHANGELOG.md` until the user confirms.

7. After confirmation, prepare the release files with:
   ```bash
   Scripts/prepare-release.sh <version> <<'EOF'
   <reviewed changelog body>
   EOF
   ```

8. Show the final diff and remind the user that publishing still requires committing the release prep and tagging `v<version>`.

## Changelog Style

Write for users and maintainers, not for the implementation diff. Prefer concise sections:

```markdown
### Added

- Added ...

### Changed

- Changed ...

### Fixed

- Fixed ...
```

Include migration notes for breaking changes. Do not include hidden implementation details unless they explain a user-visible behavior change.
