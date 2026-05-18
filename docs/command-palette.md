# Command Palette

The command palette is a fuzzy-search overlay for quickly invoking workspace actions, pane operations, and CLI commands without leaving the keyboard.

## Opening the palette

| Shortcut | Mode | Pre-fill |
| --- | --- | --- |
| `Cmd+P` | Workspace switcher | empty |
| `Cmd+Shift+P` | Command search | `>` |

You can also open it from the **View** menu.

**Workspace mode** (empty query) lists your open workspaces and lets you jump between them.

**Command mode** (query starting with `>`) lists all available commands. Type after the `>` to filter.

You can also switch mode inline: type `>` at the start of the field to enter command mode, or delete it to return to workspace mode.

Common command-mode entries include opening `~/.omux/config.toml`, reloading configuration, splitting panes, creating pane-local tabs, switching themes, and running public `omux` commands.

## Navigating

| Key | Action |
| --- | --- |
| `↑` / `↓` | Move selection |
| `Return` | Invoke selected result |
| `Escape` | Dismiss |

## Search ranking

Results are ranked in this order:

1. Exact match
2. Prefix match
3. Contains match
4. All query words appear somewhere in the candidate

An empty query shows all results in their default order.

---

## Adding a new command

Workspace actions are data-driven. In most cases you only need to add a JSON file — no Swift changes required. CLI commands are generated from the shared `OpenMUXCLICommandCatalog` so the palette stays aligned with `omux help`.

### Step 1 — create a descriptor file

Add a `.json` file to:

```
Sources/OmuxAppShell/Resources/CommandPalette/Commands/
```

The filename is used for deterministic sort order (alphabetical). Name it descriptively:

```
action-<verb>-<noun>.json   # for key-binding actions
```

### Step 2 — fill in the descriptor

```json
{
  "id":               "action:pane.split-right",
  "title":            "Split Pane Right",
  "subtitle":         "Open a new pane to the right",
  "category":         "action",
  "matchText":        "Split Pane Right vertical split open pane",
  "aliases":          ["vertical split", "split right"],
  "requiresArguments": false,
  "hasSafeDefaultTarget": true,
  "disabledReason":   "No active pane",
  "command": {
    "kind":   "action",
    "target": "pane.split-right"
  }
}
```

### Field reference

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | string | yes | Stable unique key. Use `action:` or `cli:` prefix by convention. Duplicate IDs are dropped (first file by sort order wins). |
| `title` | string | yes | Displayed in the result row. |
| `subtitle` | string | no | Secondary label shown below the title. |
| `category` | `"action"` \| `"cli"` | yes | Controls the icon shown in the result row. |
| `matchText` | string | yes | Full-text blob used for fuzzy matching. Include synonyms, descriptions, and alternative phrasings here. |
| `aliases` | array of strings | no | Additional multi-word phrases matched as search tokens. |
| `requiresArguments` | boolean | yes | Set `true` if the command needs free-form user input to run. Commands with `requiresArguments: true` are hidden unless `hasSafeDefaultTarget` is also `true`. |
| `hasSafeDefaultTarget` | boolean | yes | `true` if the command can run without arguments (has a safe built-in default). |
| `disabledReason` | string \| null | no | Message shown when the command is disabled (e.g. preconditions not met). `null` means the command is always enabled. |
| `command.kind` | `"action"` \| `"builtin"` | yes | See below. |
| `command.target` | string | yes | The action or builtin identifier. |

### `command.kind` values

**`"action"`** — maps to an `OpenMUXKeyBindingAction` by its raw string value. The full list of available targets is defined in `Sources/OmuxCore/KeyBindings.swift`. Examples:

```
workspace.create         workspace.close
workspace.move-up        workspace.move-down
pane.split-right         pane.split-down
pane.remove              pane.find        pane.next        pane.previous
pane.resize-up           pane.resize-down pane.resize-left pane.resize-right
pane.resize-equalize     sidebar.toggle
pane-tab.create          pane-tab.create-worktree          pane-tab.close
pane-tab.next            pane-tab.previous
```

**`"builtin"`** — either the app-owned `theme.switch` target, or a generated `omux` CLI command from `OpenMUXCLICommandCatalog`. Add CLI commands there instead of creating a JSON descriptor or local allow-list.

CLI commands are searchable across the full catalog. Commands without required arguments are submitted to the focused terminal. Commands that require arguments insert an editable command template into the focused terminal so you can fill placeholders before running them.

### `category` and icons

| Value | Icon (SF Symbol) |
| --- | --- |
| `"action"` | `terminal` |
| `"cli"` | `chevron.right` |

---

## Adding a new action target (Swift)

If the action you want does not exist in `OpenMUXKeyBindingAction` yet, you need a small Swift change alongside your JSON descriptor.

1. **Add the enum case** in `Sources/OmuxCore/KeyBindings.swift`:
   ```swift
   case myNewAction = "my.new-action"
   ```

2. **Add a default key binding** (optional) in `defaultBindingPairs` in the same file.

3. **Add an `isEnabled` branch** in `CommandPaletteCommands.isEnabled(action:controller:)` (`Sources/OmuxAppShell/CommandPaletteCommands.swift`):
   ```swift
   case .myNewAction:
       return controller.canDoThing()
   ```

4. **Add an invocation branch** in `invokePaletteAction(_:)` in the same file:
   ```swift
   case .myNewAction:
       controller.doThing()
   ```

5. **Create the JSON descriptor** as described above, with `"kind": "action"` and `"target": "my.new-action"`.

---

## Adding a new CLI command (Swift)

CLI commands go through the shared CLI catalog. Use this when the operation is backed by `omux` CLI semantics rather than a pure in-process action.

1. **Add a command spec** to `OpenMUXCLICommandCatalog.commands` in `Sources/OmuxCore/CLICommandCatalog.swift`.

2. **Set `requiresArguments` accurately**. Commands without required arguments are submitted to the focused terminal. Commands with required arguments insert an editable command template into the focused terminal instead of pressing Return.

3. **Update the CLI switch** in `OmuxCLICommand.run(arguments:)` if this is a new executable command.

---

## How the palette decides what is visible

A non-CLI action appears in the results only when:

- `isPaletteVisible` is `true`: either `requiresArguments == false`, or `hasSafeDefaultTarget == true`

CLI commands are always searchable so the palette covers the full `omux` surface. They are enabled when a focused terminal is available. Commands without required arguments are sent and submitted there; commands with required arguments are inserted as editable text so the user can fill placeholders before running them.

Disabled commands are shown greyed-out with the `disabledReason` text. If the user tries to invoke a disabled command, the reason is shown in the search field and the palette stays open.

---

## Architecture reference

| File | Role |
| --- | --- |
| `Sources/OmuxCore/CommandPalette.swift` | Core data types, query parsing, search and ranking |
| `Sources/OmuxCore/CLICommandCatalog.swift` | Shared `omux` command metadata used by CLI help and the palette |
| `Sources/OmuxAppShell/CommandPaletteCommandDescriptor.swift` | JSON descriptor model and bundle loading |
| `Sources/OmuxAppShell/CommandPaletteCommands.swift` | Catalog builder, `isEnabled` logic, invocation dispatcher |
| `Sources/OmuxAppShell/CommandPaletteView.swift` | AppKit overlay UI, result rows, keyboard navigation |
| `Sources/OmuxAppShell/WorkspaceWindowController.swift` | Palette presentation wired into the window |
| `Sources/OmuxAppShell/Resources/CommandPalette/Commands/` | JSON descriptor files for workspace actions |
