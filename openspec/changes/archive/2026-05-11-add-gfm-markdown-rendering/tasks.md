## 1. Dependency and Renderer Foundation

- [x] 1.1 Add a SwiftPM `swift-cmark` dependency scoped to the Markdown preview plugin target.
- [x] 1.2 Replace the hand-written Markdown block/inline parser with a `cmark-gfm` renderer wrapper.
- [x] 1.3 Attach GFM extensions for tables, task lists, strikethrough, and autolinks where available.

## 2. README HTML and Safety Constraints

- [x] 2.1 Preserve common raw README HTML such as centered paragraphs and image tags in preview output.
- [x] 2.2 Strip or neutralize script blocks and script-oriented inline attributes before the HTML reaches the extension pane host.
- [x] 2.3 Preserve the existing preview document wrapper, theme-aware style, and source-path metadata.

## 3. Tests and Documentation

- [x] 3.1 Add renderer and CLI regression tests for GFM tables, task lists, strikethrough, autolinks, fenced code, raw HTML, and script constraints.
- [x] 3.2 Update plugin documentation to describe GFM-compatible rendering and remaining host safety constraints.
- [x] 3.3 Validate the Swift test suite and OpenSpec change.

## 4. Local Image Resolution

- [x] 4.1 Resolve relative Markdown and raw HTML image sources against the Markdown file directory.
- [x] 4.2 Add regression coverage for local image source rewriting.
