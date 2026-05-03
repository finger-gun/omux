## Context

OpenMUX currently hardcodes shell-owned shortcuts in two places: AppKit menu key equivalents and `OpenMUXShortcutClassifier`. This makes defaults simple, but it gives users no escape hatch when an OpenMUX shortcut conflicts with terminal applications such as Helix, Vim, tmux, SSH sessions, or layout-specific workflows.

The config system already provides a strict OpenMUX-owned TOML surface, live reload plumbing for terminal/workspace settings, and diagnostics. Keybindings should use that same OpenMUX-native config path rather than Ghostty pass-through or app-specific hidden preferences.

## Goals / Non-Goals

**Goals:**
- Add single-chord configurable keybindings for known OpenMUX shell actions.
- Let users unbind defaults with `"none"` so conflicting chords remain terminal-owned.
- Keep built-in defaults useful without requiring config.
- Make `omux config init` write a complete default config surface, including `[keys]`.
- Share one effective keybinding registry between input classification and AppKit menu key equivalents.
- Preserve international keyboard correctness and avoid broad interception.

**Non-Goals:**
- Do not add modal keymaps, leader keys, multi-stroke sequences, or timeout state machines.
- Do not bind arbitrary shell commands, hooks, macros, or plugin actions.
- Do not make Option-based keybindings part of the default set.
- Do not expose libghostty keybinding internals as the OpenMUX config contract.

## Decisions

### Decision: Use `[keys]` as a chord-to-action table

The config SHALL use TOML entries where the key is a normalized chord string and the value is an OpenMUX action identifier or `"none"`.

Example:

```toml
[keys]
"cmd+t" = "pane-tab.create"
"cmd+w" = "pane-tab.close"
"cmd+shift+w" = "pane.remove"
"cmd+shift+backspace" = "none"
```

**Rationale:** Chord keys are easy to scan and edit, and action strings are stable contracts that can later extend to plugin/hook actions without changing the table shape.

**Alternative considered:** Nest actions first, e.g. `[keys.pane] remove = "cmd+shift+w"`. This is easier for duplicate action validation but harder to unbind a chord and less similar to editor keymap formats.

### Decision: Defaults are regular registry entries layered under user config

OpenMUX SHALL define built-in default bindings in code, then overlay user `[keys]` entries. A user entry mapping a chord to `"none"` removes any default or prior user binding for that chord.

**Rationale:** Layering keeps behavior identical without a config file and makes user overrides deterministic.

**Alternative considered:** Require users to copy the complete default map before changing any binding. That is too fragile and conflicts with the existing partial-config model.

### Decision: `omux config init` writes complete defaults

`omux config init` SHALL generate a config file that includes all current default values, not only commented examples. For optional settings where OpenMUX has an effective default, the generated file SHALL show that default explicitly. The `[keys]` table SHALL include every default binding so users can discover and edit the whole keymap.

**Rationale:** Keybindings are an edit surface. Users should not need to hunt through docs to know what can be changed, especially when resolving conflicts with terminal applications.

**Alternative considered:** Keep a sparse starter config and document defaults separately. That makes `config init` less useful for keybinding customization.

### Decision: Reject unsafe or ambiguous bindings with diagnostics

The keybinding loader SHALL validate chord syntax, known action identifiers, duplicate effective chords, and unsupported modifiers. Option/right-Option chords SHALL be rejected for v1 unless a future spec explicitly allows them.

**Rationale:** Keyboard correctness is a core requirement. Rejecting risky bindings is safer than allowing config to silently break international text input.

**Alternative considered:** Accept arbitrary modifier strings and rely on users to fix mistakes. That would make config more flexible but would likely create hard-to-debug terminal input failures.

### Decision: Single effective registry feeds input and menus

The effective keybinding registry SHALL answer two questions:

1. Does this normalized input event match an OpenMUX action?
2. What AppKit menu key equivalent should represent this action?

```
~/.omux/config.toml
        │
        ▼
  OmuxConfig.keys
        │
        ▼
KeyBindingRegistry
   │           │
   ▼           ▼
input       AppKit menus
classifier
```

**Rationale:** Divergence between menu display and terminal interception would make shortcuts surprising. A shared registry keeps the UI and input pipeline coherent.

**Alternative considered:** Leave menus static and only make the input classifier configurable. That would make configured shortcuts invisible in native menus.

## Risks / Trade-offs

- **Risk:** Configured shortcuts conflict with terminal app workflows. -> **Mitigation:** Support `"none"` unbinding and keep unbound/unknown chords terminal-owned.
- **Risk:** Option bindings break EU/ISO layouts and right-Option text. -> **Mitigation:** Reject Option chords in v1 and document why.
- **Risk:** AppKit cannot represent every parsed chord as a native menu equivalent. -> **Mitigation:** Apply representable chords to menus and keep non-representable safe chords input-only with diagnostics if needed.
- **Risk:** Live reload leaves menus/input registry out of sync. -> **Mitigation:** Update both from configuration coordinator changes in one main-actor application step.
- **Risk:** Action identifiers become accidental public API. -> **Mitigation:** Document only the supported action namespace and validate unknown values.

## Migration Plan

- Keep all existing default shortcuts except shortcuts explicitly removed by the active shortcut-ladder change.
- Generate `[keys]` in new configs via `omux config init`.
- Existing user configs without `[keys]` continue using built-in defaults.
- Users can opt out of any default by adding `"chord" = "none"`.

## Open Questions

- Whether future keymaps should support modal/leader-style sequences after the single-chord registry is stable.
- Whether plugin or hook actions should share the same action namespace or use a separate prefix later.
