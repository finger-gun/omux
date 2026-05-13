## ADDED Requirements

### Requirement: Extension registries SHALL expose TOML catalogs
OpenMUX SHALL discover remote hook and plugin packages from TOML registry catalogs. Catalog entries SHALL include package kind, id, name, description, version, registry source, package path, and optional tags.

#### Scenario: Discover official plugin catalog
- **WHEN** the user runs `omux plugins discover`
- **THEN** OpenMUX fetches the configured plugin registry catalogs and lists available plugin packages

#### Scenario: Discover official hook catalog
- **WHEN** the user runs `omux hooks discover`
- **THEN** OpenMUX fetches the configured hook registry catalogs and lists available hook packages

#### Scenario: JSON discovery output
- **WHEN** the user runs discovery with `--json`
- **THEN** OpenMUX prints machine-readable package entries including registry source and package id

### Requirement: Extension registries SHALL support custom registry URLs
OpenMUX SHALL support official default registries and custom registry URLs supplied through CLI flags or user configuration. CLI `--registry` values SHALL apply to the current command invocation.

#### Scenario: CLI registry override
- **WHEN** the user runs `omux plugins discover --registry https://github.com/example/omux-plugins`
- **THEN** OpenMUX discovers packages from the supplied registry for that command

#### Scenario: Configured registry
- **WHEN** `~/.omux/config.toml` configures plugin or hook registry URLs
- **THEN** OpenMUX uses those registry URLs for matching discovery and install commands when no CLI registry override is provided

### Requirement: Extension packages SHALL use validated TOML manifests
Remote hook and plugin packages SHALL declare schema-versioned TOML manifests. Hook manifests SHALL declare the hook name/category and file entries. Plugin manifests SHALL declare command name, entrypoint, and file entries.

#### Scenario: Valid hook manifest
- **WHEN** a hook package manifest declares schema, id, kind `hook`, hook metadata, and file entries
- **THEN** OpenMUX can validate it as an installable hook package

#### Scenario: Valid plugin manifest
- **WHEN** a plugin package manifest declares schema, id, kind `plugin`, plugin metadata, and file entries
- **THEN** OpenMUX can validate it as an installable plugin package

#### Scenario: Invalid manifest rejected
- **WHEN** a package manifest has an unsupported schema, invalid id, missing entrypoint, or invalid hook metadata
- **THEN** OpenMUX rejects the package with a clear diagnostic and does not install files

### Requirement: Extension install SHALL stage and validate files before copying
OpenMUX SHALL download package files into a temporary staging location, validate all source and target paths, set executable permissions from manifest metadata, and copy files only into the appropriate OpenMUX extension directory.

#### Scenario: Plugin install copies to plugin directory
- **WHEN** the user installs a valid plugin package
- **THEN** OpenMUX copies the package files under `~/.omux/plugins/<plugin-command>/` and makes the declared entrypoint executable

#### Scenario: Hook install copies to hook directory
- **WHEN** the user installs a valid hook package
- **THEN** OpenMUX copies declared handler files under `~/.omux/hooks/<hook-name>/` and makes declared executable files executable

#### Scenario: Unsafe paths rejected
- **WHEN** a package file source or target is absolute, contains `..`, or escapes the staging or install root
- **THEN** OpenMUX rejects installation and does not write package files

### Requirement: Extension install SHALL record receipts
OpenMUX SHALL record install receipts for registry-installed hook and plugin packages. Receipts SHALL include package kind, id, version, registry source, manifest path, installed files, and install time.

#### Scenario: Install writes receipt
- **WHEN** OpenMUX successfully installs a remote package
- **THEN** it writes a receipt that can be used for later update or uninstall

#### Scenario: Uninstall refuses unmanaged package
- **WHEN** the user asks OpenMUX to uninstall a package without an install receipt
- **THEN** OpenMUX refuses to delete files by package id alone and explains that the package is unmanaged

### Requirement: Extension package lifecycle commands SHALL be explicit
OpenMUX SHALL expose CLI commands to discover, install, update, and uninstall remote hook and plugin packages without changing existing local plugin picker behavior.

#### Scenario: Plugin install command
- **WHEN** the user runs `omux plugins install <plugin-id>`
- **THEN** OpenMUX resolves a matching plugin package from configured registries and installs it

#### Scenario: Hook install command
- **WHEN** the user runs `omux hooks install <hook-id>`
- **THEN** OpenMUX resolves a matching hook package from configured registries and installs it

#### Scenario: Update uses receipt source
- **WHEN** the user runs `omux plugins update <plugin-id>` or `omux hooks update <hook-id>`
- **THEN** OpenMUX uses the recorded receipt source to resolve and replace the installed package

#### Scenario: Uninstall removes receipt-managed files
- **WHEN** the user runs `omux plugins uninstall <plugin-id>` or `omux hooks uninstall <hook-id>`
- **THEN** OpenMUX removes files recorded in the package receipt and then removes the receipt

### Requirement: Extension install SHALL disclose executable-code trust
OpenMUX SHALL clearly identify package source, version, and target paths before installing executable hook or plugin code. Non-interactive installs SHALL require an explicit confirmation flag.

#### Scenario: Interactive install disclosure
- **WHEN** the user installs a package from a registry in an interactive terminal
- **THEN** OpenMUX prints the package id, version, registry URL, and target paths before asking for confirmation

#### Scenario: Non-interactive install requires yes
- **WHEN** the user installs a package without an interactive confirmation source
- **THEN** OpenMUX requires `--yes` or exits without installing files
