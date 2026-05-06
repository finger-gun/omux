## Context

The bundled Markdown preview plugin currently renders Markdown with a small local parser that supports only headings, paragraphs, unordered lists, code fences, inline code, and basic links. That was sufficient to prove extension panes, but it does not match common README expectations: raw HTML blocks are escaped, GFM tables and task lists are not supported, and GitHub-style autolinks/strikethrough do not render.

The renderer lives in `Sources/Plugins/MarkdownPreview`, which is the correct boundary for Markdown-specific behavior. The app shell only receives local HTML through extension-pane descriptors and hosts it in a constrained `WKWebView` with JavaScript disabled and navigation policy enforcement.

## Goals / Non-Goals

**Goals:**

- Use a real GFM-capable parser for Markdown preview rendering.
- Preserve the existing `omux markdown-preview` CLI and extension-pane update flow.
- Keep renderer behavior plugin-owned and replaceable.
- Render raw README HTML such as centered paragraphs and image tags while preventing script execution.
- Keep tests focused on user-visible README fidelity and unsafe-content constraints.

**Non-Goals:**

- Exact GitHub.com rendering parity, including all CSS, heading anchors, alerts, Mermaid, syntax highlighting, or GitHub API enrichment.
- A general browser surface inside OpenMUX.
- A new plugin runtime, renderer daemon, or core Markdown APIs.
- Changes to terminal input, Ghostty surfaces, or workspace layout contracts.

## Decisions

### Decision: Use `swift-cmark` / `cmark-gfm` directly for HTML rendering

The Markdown preview plugin should depend on SwiftPM's `swift-cmark` package and call the `cmark-gfm` C API from Swift. The renderer will attach the GFM extensions needed for README fidelity: `table`, `strikethrough`, `tasklist`, and `autolink` when available. It will render an HTML fragment with GFM options, then wrap it in the existing preview document and style.

Alternatives considered:

- **Apple Swift Markdown AST only:** It is powered by `cmark-gfm`, but it does not directly provide a complete HTML renderer for preview use. Building a full HTML visitor would duplicate rendering logic and risk mismatches.
- **Keep expanding the hand-written renderer:** This would keep dependencies minimal but continue to chase GFM edge cases poorly.
- **Shell out to a `cmark-gfm` executable:** This avoids C interop but adds process overhead, deployment assumptions, and worse error handling.

Direct `cmark-gfm` keeps the renderer close to GitHub's parser while staying inside the optional plugin target.

### Decision: Allow raw HTML for README fidelity but sanitize script-oriented content

GFM raw HTML must be rendered for README patterns such as badges, centered logos, and explicit image/layout tags. The renderer will enable raw HTML output, then strip script blocks and script-oriented attributes before handing HTML to the extension pane. The WebKit host remains a second defense layer by disabling JavaScript and preventing in-pane browser navigation.

Alternatives considered:

- **Disable raw HTML:** Safer, but it does not solve the user's README problem.
- **Full HTML sanitizer dependency:** More complete, but heavier than needed for a local preview plugin at this stage.

This is not a security sandbox; it is a constrained local preview path. The docs should be explicit about that boundary.

### Decision: Keep the extension-pane payload contract unchanged

The renderer still returns a full HTML document string. `omux markdown-preview` still creates or updates an extension pane with `contentKind = html`. No control-plane or app-shell schema changes are needed.

Alternatives considered:

- **Send Markdown to the app shell and render there:** Violates plugin isolation and makes Markdown a core shell concern.
- **Introduce a custom preview content kind:** Unnecessary until multiple renderer types need richer host integration.

## Risks / Trade-offs

- **External dependency build risk** -> Pin through SwiftPM resolution and validate in the existing test workflow.
- **Raw HTML risk** -> Strip script-oriented content in the plugin and keep JavaScript disabled in the host.
- **Rendering parity expectations** -> Document this as GFM-compatible local preview, not exact GitHub.com output.
- **Performance on large files** -> `cmark-gfm` is native and fast; hot reload continues to render only after file modification changes.
- **Plugin dependency scope creep** -> Limit the new dependency to `OmuxMarkdownPreviewPlugin`.

## Migration Plan

1. Add the `swift-cmark` package dependency and wire `cmark-gfm` products only into the Markdown preview plugin target.
2. Replace the custom renderer block/inline parser with a `cmark-gfm` renderer wrapper.
3. Add tests for raw HTML, GFM tables, task lists, strikethrough, autolinks, fenced code blocks, and script constraints.
4. Update plugin docs to describe GFM-compatible rendering and raw HTML constraints.
5. Run the existing Swift and OpenSpec validation workflows.

Existing user configuration remains valid. The `renderer = "builtin"` setting continues to mean the bundled renderer, now backed by `cmark-gfm`.

## Open Questions

- Whether to add GitHub-like heading anchors and syntax highlighting later as separate optional renderer enhancements.
- Whether to add a stronger sanitizer dependency if external plugin scenarios require less trusted content than local project README files.
