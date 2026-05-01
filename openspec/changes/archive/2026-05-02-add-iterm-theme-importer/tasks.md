## 1. Import Pipeline

- [x] 1.1 Add a pinned upstream ref file and manifest listing the selected imported themes.
- [x] 1.2 Add a `Scripts/import-iterm2-themes.sh` script that reads the manifest, fetches upstream Ghostty-format theme files, validates required colors, and emits complete OpenMUX theme TOML.
- [x] 1.3 Ensure generated TOML includes source comments with upstream repository, ref, and source theme name.

## 2. Theme Resources

- [x] 2.1 Run the importer to generate the built-in theme resources.
- [x] 2.2 Review generated resources for complete token coverage and deterministic identifiers/display names.

## 3. Tests and Documentation

- [x] 3.1 Update theme tests to assert the expanded built-in theme set and importer-generated theme loadability.
- [x] 3.2 Update configuration/development documentation to list the expanded built-in presets and importer workflow.
- [x] 3.3 Run the relevant Swift tests and OpenSpec validation for the change.
