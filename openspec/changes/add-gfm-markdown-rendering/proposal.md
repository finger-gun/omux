## Why

The Markdown preview plugin currently uses a small hand-written renderer, so common README patterns such as raw HTML blocks, tables, task lists, and other GitHub Flavored Markdown features do not render like they do on GitHub. Improving renderer fidelity makes the terminal-editor-plus-preview workflow useful for real project documentation without moving Markdown behavior into the terminal core.

## Goals

- Render Markdown preview content with GitHub Flavored Markdown-compatible behavior for common README files.
- Preserve the optional bundled plugin model and keep Markdown-specific logic isolated under the Markdown preview plugin.
- Keep preview hosting constrained: no arbitrary JavaScript execution, no browser chrome, and external navigation handled by OpenMUX.
- Preserve hot reload behavior and the existing `omux markdown-preview` command contract.
- Keep terminal input handling and the libghostty bridge unaffected.

## Non-goals

- Do not turn OpenMUX into a browser-first shell or general web app runtime.
- Do not add GitHub API dependencies, network rendering, Mermaid rendering, PDF export, or exact GitHub.com visual parity.
- Do not move Markdown parsing/rendering into `OmuxCore`, `OmuxTerminalBridge`, or workspace layout code.
- Do not introduce an always-on renderer daemon.

## What Changes

- Replace the Markdown preview plugin's minimal renderer with a renderer backed by a real Markdown/GFM parsing implementation.
- Render common GFM README features, including raw HTML blocks, tables, task lists, strikethrough, autolinks, fenced code blocks, and inline HTML.
- Keep unsafe behavior constrained by the existing extension-pane WebKit host: JavaScript remains disabled and link navigation remains controlled by OpenMUX.
- Add regression tests covering GFM examples that currently fail or render as escaped text.
- Update Markdown preview documentation to describe GFM-compatible rendering and security constraints.

## Capabilities

### New Capabilities

- `markdown-preview-gfm-rendering`: Covers GFM-compatible rendering expectations for the Markdown preview plugin.

### Modified Capabilities

- None.

## Impact

- **Markdown preview plugin:** Renderer implementation and tests change under `Sources/Plugins/MarkdownPreview`.
- **Dependencies:** The Swift package may gain a Markdown/GFM parser dependency or a small bridge to a system parser if it preserves the same build/test workflow.
- **Extension panes:** No contract change; rendered HTML still flows through the existing extension-pane descriptor payload.
- **Security:** Raw HTML may be rendered for README fidelity, but JavaScript execution remains disabled in the host and navigation remains constrained.
- **libghostty boundary:** No impact; terminal rendering and input stay behind `OmuxTerminalBridge`.
- **Keyboard/input:** No change to terminal keyboard semantics, including EU/ISO layouts, Option/Alt behavior, right-Option, dead keys, compose keys, or IME paths.
