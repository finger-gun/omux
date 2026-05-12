## Context

OpenMUX currently has two local extensibility mechanisms:

- hooks are executable files discovered under `~/.omux/hooks/<hook-name>/`
- CLI plugins are executables discovered under `~/.omux/plugins/`, with bundled plugins listed by the existing plugin registry

These mechanisms are terminal-first and language-neutral, but users have no built-in way to discover or install shared hooks/plugins. The new `finger-gun/omux-hooks` and `finger-gun/omux-plugins` repositories provide a natural place to host official packages, and users should also be able to point OpenMUX at custom registries.

## Goals / Non-Goals

**Goals:**

- Add explicit TOML package and catalog contracts for remote hooks/plugins.
- Add official default registries and custom registry URL support.
- Add CLI discovery, install, update, and uninstall commands.
- Install packages into the existing local directories so runtime hook/plugin discovery stays unchanged.
- Validate paths and write receipts so installs are inspectable and reversible.

**Non-Goals:**

- No GUI marketplace, browser-heavy discovery UI, or background registry service.
- No embedded plugin runtime or sandbox in this change.
- No automatic execution of package code during install.
- No changes to libghostty, terminal surface hosting, or keyboard input routing.

## Decisions

### Use TOML manifests and catalogs

Registry roots expose `catalog.toml`, and packages expose `omux-hook.toml` or `omux-plugin.toml`. TOML matches the existing OpenMUX configuration tooling and avoids adding YAML or JSON schema dependencies.

Alternatives considered:

- YAML: familiar for package metadata, but requires a new parser and broadens the dependency surface.
- JSON: easy to parse, but less friendly for hand-authored registry files than TOML.

### Keep runtime discovery local

The installer copies files into `~/.omux/hooks` or `~/.omux/plugins`; the app and plugin runner continue using the existing local discovery contracts. Receipts are used for install management only.

Alternatives considered:

- Runtime discovery directly from remote registries: rejected because it requires network access during normal app use and creates surprising execution behavior.
- New remote package runtime: rejected as unnecessary core complexity.

### Support official defaults and custom registries

OpenMUX defaults to the official `finger-gun` repositories, while `--registry` flags and `[registries]` config entries allow custom sources. CLI flags take precedence for the command invocation.

Alternatives considered:

- Official repositories only: simpler, but too closed for OpenMUX's hackability goals.
- Arbitrary package URLs only: flexible, but less discoverable and harder to secure than registry catalogs.

### Fetch catalog/package files through explicit URL resolution

GitHub repository URLs resolve to raw `catalog.toml` and raw package file URLs. Explicit raw catalog URLs can also be accepted. The implementation should keep URL normalization isolated in the registry client.

Alternatives considered:

- Shelling out to `git clone`: rejected because it adds tool availability, performance, and cleanup concerns.
- Downloading and unpacking archives only: useful later, but raw manifest file installs are simpler to validate for the first implementation.

### Use install receipts

OpenMUX writes receipts for installed remote packages so uninstall/update do not delete unrelated manually-created local hooks/plugins. Receipts record package id, kind, registry URL, version, manifest path, installed files, and install time.

Alternatives considered:

- Delete by package id without receipts: unsafe for users who hand-manage directories.
- Store state only in `config.toml`: mixes package manager state into user-authored config and risks noisy rewrites.

## Risks / Trade-offs

- Custom registries install executable code → print registry, version, and target paths before install; require `--yes` for non-interactive installs and avoid executing package code during install.
- Remote network failures can make discovery flaky → report clear errors and keep installed packages independent of remote availability.
- Path traversal or symlink escapes could overwrite user files → reject absolute paths, `..`, hidden control targets, and symlinks escaping staging/install roots.
- The first package format may evolve → schema-version manifests and receipts give future migration points.
- Multiple registries may contain the same id → qualify results by registry source and make ambiguous installs fail unless one registry is selected.

## Migration Plan

Existing hooks/plugins continue working because runtime discovery remains local. The new commands only add metadata-managed installs. Users can uninstall remote packages via receipts or manually remove local files if needed.

Rollback is safe by removing installed package files and receipts; OpenMUX then falls back to the existing local discovery behavior.

## Open Questions

- Whether disable/enable should be implemented as receipt state, file renaming, or deferred to uninstall/reinstall.
- Whether later registry catalogs should be generated from package manifests in CI for the official repositories.
