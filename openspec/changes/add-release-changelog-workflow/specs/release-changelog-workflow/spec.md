## ADDED Requirements

### Requirement: Product version source of truth
OpenMUX SHALL maintain a committed `VERSION` file containing the current product semantic version without a leading `v`.

#### Scenario: Local package release uses VERSION by default
- **WHEN** `make package-release` is run without `RELEASE_VERSION`
- **THEN** the package release flow SHALL use the semantic version from `VERSION`

#### Scenario: Explicit release version override
- **WHEN** `make package-release RELEASE_VERSION=0.3.0` is run
- **THEN** the package release flow SHALL use `0.3.0` instead of the value in `VERSION`

#### Scenario: App bundle marketing version
- **WHEN** release packaging creates `OpenMUX.app`
- **THEN** `CFBundleShortVersionString` SHALL equal the selected semantic release version
- **AND** `CFBundleVersion` SHALL equal the selected build number

### Requirement: Release change analysis
OpenMUX SHALL provide a repository-local command that reports changes since the latest `v*` release tag and groups changed files by OpenMUX release surface.

#### Scenario: Latest tag exists
- **WHEN** the release analysis command runs in a repository with at least one `v*` tag
- **THEN** it SHALL report the latest release tag, commits since that tag, and changed files since that tag

#### Scenario: No release tag exists
- **WHEN** the release analysis command runs in a repository with no `v*` tags
- **THEN** it SHALL report that no previous release tag exists
- **AND** it SHALL analyze commits and files from the available repository history

#### Scenario: Changed files are grouped by surface
- **WHEN** changed files include paths under known OpenMUX areas
- **THEN** the release analysis command SHALL group them under surfaces such as CLI, app shell, terminal bridge, config, hooks, themes, packaging, documentation, OpenSpec, vendored Ghostty, or other

### Requirement: Release preparation
OpenMUX SHALL provide a repository-local command that prepares a release by validating a target semantic version, updating `VERSION`, and prepending a changelog section to `CHANGELOG.md`.

#### Scenario: Preparing a valid release
- **WHEN** the release preparation command is given target version `0.3.0` and changelog body input
- **THEN** it SHALL update `VERSION` to `0.3.0`
- **AND** it SHALL prepend a `## 0.3.0` section to `CHANGELOG.md`

#### Scenario: Invalid semantic version
- **WHEN** the release preparation command is given a target version that is not `MAJOR.MINOR.PATCH`
- **THEN** it SHALL fail without changing `VERSION` or `CHANGELOG.md`

#### Scenario: Missing changelog body
- **WHEN** the release preparation command is not given changelog body input
- **THEN** it SHALL fail without changing `VERSION` or `CHANGELOG.md`

### Requirement: Agent-authored release note skill
OpenMUX SHALL include a project skill that guides agents through release note creation by analyzing repository changes since the latest release and asking for confirmation before writing release files.

#### Scenario: Skill analyzes before writing
- **WHEN** an agent uses the release note skill
- **THEN** the skill SHALL instruct the agent to inspect changes since the latest `v*` tag, group the changes by OpenMUX surface, recommend a semver bump, and explain the reasoning before writing files

#### Scenario: Skill requires confirmation
- **WHEN** the agent has drafted a changelog section and target version
- **THEN** the skill SHALL instruct the agent to ask for user confirmation before updating `VERSION` or `CHANGELOG.md`

### Requirement: Tag-triggered release compatibility
The GitHub Release workflow SHALL remain compatible with pushed `v*` tags and package artifacts using the version represented by the tag.

#### Scenario: GitHub release packaging
- **WHEN** a tag named `v0.3.0` triggers the release workflow
- **THEN** release artifacts SHALL be packaged with release version `0.3.0`

#### Scenario: Generated release notes can use committed changelog
- **WHEN** a maintainer reviews a release
- **THEN** `CHANGELOG.md` SHALL contain the committed release notes for the version being tagged
