## Context

OpenMUX already hosts terminal panes through `OmuxTerminalBridge`, forwards pointer events to the runtime, exposes bounded terminal text snapshots, tracks pane working directories, and provides hooks plus extension panes. Markdown preview already renders local Markdown in a plugin-owned extension pane.

The new behavior should connect those pieces without making Markdown a terminal-core feature. The core concept is "terminal text activation": a user intentionally activates a token in terminal output, and OpenMUX emits structured context that plugins can handle.

## Goals / Non-Goals

**Goals:**

- Modifier-click terminal text and derive a token under the pointer.
- Resolve local path-like tokens relative to the pane's reported/current working directory.
- Emit an input hook event for activated text.
- Handle readable Markdown paths with the enabled bundled Markdown preview plugin.
- Preserve normal terminal pointer semantics for unmodified clicks.

**Non-Goals:**

- Perfect terminal cell-to-string mapping for every font, ligature, wide glyph, wrapped line, alternate screen, and scrollback case.
- Plain-click activation.
- A full plugin priority/claim protocol in the first slice.
- Blocking terminal input on slow external hooks.

## Decisions

### Decision: Activation requires an explicit modifier

Command-click is the primary activation gesture on macOS. Shift-click can be considered an alias only if it does not interfere with selection or terminal mouse semantics. Plain clicks always continue to the terminal runtime.

Alternatives considered:

- **Plain click:** too disruptive for shell prompts, TUIs, selection, and mouse reporting.
- **Context menu only:** safer, but less ergonomic and less like terminal URL activation.

### Decision: Hit-testing is best-effort and OpenMUX-native

The runtime host will translate the pointer location to an approximate terminal row/column using the hosted view bounds and measured terminal size. The bridge/app shell can use visible terminal text snapshots to extract a token at that row/column. Tokenization should prefer file/URL-safe characters and trim shell punctuation.

Alternatives considered:

- **Require libghostty hyperlink APIs first:** likely more accurate for URLs, but does not solve local path tokens from `ls`.
- **OCR/accessibility text lookup:** too fragile and indirect.

### Decision: Emit hooks before bundled plugin handling

OpenMUX should emit `terminal-text-activated` in the `input` hook category with token, cwd, resolved path, modifiers, pane/session/workspace IDs, and activation kind. The bundled Markdown preview handler then handles Markdown paths when enabled. Hooks are observational in this first slice; a future claim protocol can allow external plugins to consume activation.

Alternatives considered:

- **Only invoke Markdown preview:** useful but too narrow and not plugin-friendly.
- **Synchronous external claim chain:** extensible, but more complex and risks making pointer handling depend on subprocess latency.

### Decision: Markdown preview uses existing extension-pane flow

The bundled handler should render and open/update an extension pane through the same app-shell/controller path as `omux markdown-preview`, not duplicate preview hosts or terminal bridge behavior.

## Risks / Trade-offs

- **Hit-test inaccuracy** -> Limit first version to visible text, document best-effort behavior, and test predictable monospace snapshots.
- **Terminal input regression** -> Only intercept modified clicks that successfully activate a local Markdown path; otherwise forward pointer events to the runtime.
- **Hook latency** -> Emit hooks from the app shell after activation detection; do not wait for hook completion before returning pointer control.
- **Plugin coupling** -> Keep Markdown handling behind plugin enablement and reuse `dev.fingergun.markdown-preview` identity.

## Migration Plan

1. Add activation event types and token extraction helpers.
2. Thread an optional activation callback from app shell through hosted terminal views.
3. Emit an input hook event for activations.
4. Add bundled Markdown preview handling for readable local Markdown paths.
5. Document gesture and payload, then validate tests and OpenSpec.

## Open Questions

- Whether a future version should add a formal external plugin claim/priority protocol.
- Whether Shift-click should be a default alias or remain available for selection-oriented terminal behavior.
