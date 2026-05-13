## 1. Contracts and Configuration

- [x] 1.1 Add registry URL configuration models, defaults, TOML parsing, validation diagnostics, rendering, and config init output.
- [x] 1.2 Add extension registry/package/receipt models with validation for package kind, id, version, hook metadata, plugin metadata, file entries, and safe relative paths.
- [x] 1.3 Add tests for config registry URL parsing, defaults, invalid values, and rendered starter config.

## 2. Catalog Discovery

- [x] 2.1 Implement registry source resolution from official defaults, config, and `--registry` CLI flags.
- [x] 2.2 Implement catalog fetching/parsing for GitHub repository URLs and explicit catalog/raw URLs.
- [x] 2.3 Implement text and JSON discovery output for hook and plugin package catalogs.
- [x] 2.4 Add tests for catalog parsing, registry URL normalization, duplicate/ambiguous packages, and discovery output.

## 3. Installation Lifecycle

- [x] 3.1 Implement package file download into temporary staging without executing package code.
- [x] 3.2 Implement path traversal, absolute path, and install-root escape protection for all package files.
- [x] 3.3 Implement hook install into `~/.omux/hooks/<hook-name>/` and plugin install into `~/.omux/plugins/<plugin-command>/`.
- [x] 3.4 Implement install receipts, uninstall by receipt, and update using receipt source.
- [x] 3.5 Add tests for install layout, executable permissions, receipt contents, unmanaged uninstall refusal, update, and unsafe path rejection.

## 4. CLI Integration

- [x] 4.1 Wire `omux hooks discover/install/uninstall/update` with `--registry`, `--json`, and `--yes` where applicable.
- [x] 4.2 Wire `omux plugins discover/install/uninstall/update` while preserving `omux plugins` picker and `omux plugin list|path`.
- [x] 4.3 Add confirmation/disclosure output before installing executable packages, including non-interactive `--yes` handling.
- [x] 4.4 Add CLI routing tests for new hook/plugin commands and preservation of existing plugin behavior.

## 5. Documentation and Validation

- [x] 5.1 Update hook and plugin docs with registry repository layout, TOML metadata examples, command usage, custom registries, and trust guidance.
- [x] 5.2 Run relevant config, CLI, hook, and app shell tests.
- [x] 5.3 Run `openspec validate add-remote-extension-registries --strict`.
