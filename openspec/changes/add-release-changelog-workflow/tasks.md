## 1. Version and changelog foundations

- [x] 1.1 Add a root `VERSION` file containing the current OpenMUX product semantic version.
- [x] 1.2 Add a root `CHANGELOG.md` with an initial project changelog structure.

## 2. Release tooling

- [x] 2.1 Add a repository-local release analysis script that finds the latest `v*` tag, reports commits/files since that tag, and groups changed files by OpenMUX release surface.
- [x] 2.2 Add a repository-local release preparation script that validates a `MAJOR.MINOR.PATCH` target version, requires changelog body input, updates `VERSION`, and prepends a `## <version>` changelog section.
- [x] 2.3 Ensure release preparation fails without changing files when the version or changelog input is invalid.

## 3. Packaging integration

- [x] 3.1 Update local package release behavior so `make package-release` uses `VERSION` when `RELEASE_VERSION` is not provided.
- [x] 3.2 Preserve explicit `RELEASE_VERSION` overrides and tag-derived GitHub release packaging.
- [x] 3.3 Ensure packaged app bundles still map release semver to `CFBundleShortVersionString` and build numbers to `CFBundleVersion`.

## 4. Agent workflow

- [x] 4.1 Add a project skill for OpenMUX release note creation.
- [x] 4.2 Make the skill instruct agents to analyze changes since the latest `v*` tag, group by OpenMUX surface, recommend a semver bump, explain reasoning, draft changelog notes, and ask before writing.

## 5. Documentation and validation

- [x] 5.1 Update release and development documentation for the `VERSION`, changelog, analysis, preparation, and package release workflow.
- [x] 5.2 Validate the new release scripts, OpenSpec change, and existing build/test workflow.
