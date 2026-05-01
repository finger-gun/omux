## Context

OpenMUX already represents themes as flat TOML resources with a closed token vocabulary. The runtime theme registry and compiler are intentionally OpenMUX-owned: they load bundled/user TOML, compile explicit colors into generated Ghostty config files, and avoid reading external Ghostty config or theme directories.

The iTerm2 Color Schemes repository publishes many schemes in Ghostty config format. That format contains the terminal-facing colors OpenMUX already needs (`background`, `foreground`, cursor, selection, and ANSI `palette` entries), but it does not contain OpenMUX-specific shell chrome tokens such as `bg.elevated`, borders, or muted text. The importer therefore needs to normalize upstream terminal palette files into the existing OpenMUX token model without introducing runtime dependency on upstream files.

## Goals / Non-Goals

**Goals:**

- Add a development/maintenance script for importing selected upstream Ghostty-format schemes into OpenMUX theme TOML.
- Keep imported themes deterministic by using an explicit manifest with output identifiers, display names, source names, and a pinned upstream ref.
- Validate upstream files before writing theme resources so missing color keys fail loudly.
- Generate OpenMUX-only shell chrome tokens through deterministic derivation from the imported terminal palette.
- Add imported built-in themes while preserving the existing default.

**Non-Goals:**

- No runtime online fetching, theme browsing, or background synchronization.
- No new Swift package dependency or external package manager requirement.
- No direct use of Ghostty theme names by the runtime compiler.
- No changes to terminal input, keymaps, Option/Alt handling, dead keys, compose keys, or IME behavior.

## Decisions

### Use a POSIX shell script with embedded Swift for parsing and generation

The repo already uses `Scripts/*.sh` for development workflows. A shell entrypoint fits that convention and can handle repository paths, manifest iteration, `curl`, and temporary directories. Embedded Swift is appropriate for the actual parser/generator because the project is already Swift-based and Swift gives safer string handling for validation and deterministic TOML emission than complex shell text processing.

Alternative considered: add a compiled Swift command target. That is heavier for a maintenance-only tool and would expand package surface area. If theme import becomes user-facing later, the importer can be promoted into a proper target.

### Import from upstream Ghostty-format files, not iTerm plist files

The upstream Ghostty files already express the exact terminal color contract that OpenMUX emits back to Ghostty. Importing them avoids plist parsing and keeps the transformation narrow.

Alternative considered: parse `.itermcolors` directly. That would support more upstream source formats but adds parsing complexity with no immediate benefit for the selected themes.

### Manifest-driven selection

The importer reads a checked-in manifest where each non-comment row defines:

```text
output-id | upstream-name | display-name
```

This keeps the chosen built-ins reviewable and prevents accidentally importing every available upstream theme.

Alternative considered: command-line theme names only. That is useful for ad hoc experiments but less reproducible for committed built-ins.

### Deterministic chrome-token derivation

Terminal-facing tokens are copied directly from upstream colors. OpenMUX shell tokens are derived as follows:

| OpenMUX token | Derivation |
| --- | --- |
| `bg.canvas` | `background` |
| `bg.surface` | `background` |
| `bg.elevated` | ANSI bright black (`palette 8`), fallback `selection-background` |
| `fg.primary` | `foreground` |
| `fg.secondary` | ANSI white (`palette 7`), fallback `foreground` |
| `fg.muted` | ANSI bright black (`palette 8`), fallback `foreground` |
| `border.subtle` | ANSI bright black (`palette 8`), fallback `selection-background` |
| `border.strong` | `selection-background` |
| `accent` | ANSI bright blue (`palette 12`), fallback `cursor-color` |

This biases toward preserving terminal color fidelity and giving shell chrome stable, readable defaults. Individual themes can be hand-tuned later if design review identifies contrast issues, but the importer should first be predictable.

### Keep source metadata as comments

Generated TOML files include comments naming the upstream repository, ref, and upstream theme name. The loader ignores comments, and maintainers can audit provenance when refreshing or reviewing themes.

## Risks / Trade-offs

- Upstream individual theme licensing varies within the MIT-licensed collection -> Keep source metadata and selected-theme attribution visible for review; do not hide the origin of generated files.
- Derived shell tokens may not be ideal for every palette -> Use deterministic rules now, then allow targeted manual refinement or better contrast derivation in a future change.
- Floating upstream changes could make imports non-reproducible -> Pin the upstream ref in the manifest-adjacent ref file and allow explicit override only when intentionally refreshing.
- Network dependency during import could fail -> Make failures loud and leave existing checked-in generated themes untouched unless a source fetch succeeds.

## Migration Plan

1. Add the importer script and manifest/ref files.
2. Run the importer to generate new theme TOML files under the existing bundled resource directory.
3. Update tests and docs to include the expanded built-in set.
4. Runtime migration is unnecessary because theme loading already discovers bundled TOML resources.

Rollback is deleting the generated theme files and importer artifacts from the change; no persisted user configuration schema changes are involved.

## Open Questions

- Should future theme imports include a generated attribution document, or are per-file source comments plus upstream license documentation sufficient?
- Should the importer grow optional contrast checks for shell chrome tokens before more themes are added?
