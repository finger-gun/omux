# AGENTS.md

This document gives project-specific guidance to AI agents and other automated contributors working in the OpenMUX repository.

## Project north star

OpenMUX is a **fast, flexible, and hackable terminal workspace for developers**.

The terminal is the product.
Not AI.
Not a browser.
Not a sidecar experience.

OpenMUX should be:

- **Open by design**
- **Terminal first**
- **Hackable**
- **Composed from tools, not opinions**
- **Performance-conscious**
- **International-first**
- **AI-friendly by design**

Read these first before making architectural decisions:

- [`docs/manifest.md`](./docs/manifest.md)
- [`docs/research/**`](./docs/research/)

## Current intended architecture

Until the codebase proves otherwise, assume the current target direction is:

- **Platform:** macOS-only for v1
- **Desktop shell:** AppKit-first, with selective SwiftUI for non-terminal chrome
- **Language/tooling:** Swift, Xcode, Swift Package Manager
- **Terminal engine:** pinned `libghostty`
- **Boundary rule:** `libghostty` should sit behind one narrow OpenMUX bridge/module
- **CLI:** `omux`
- **IPC:** JSON-RPC over a Unix domain socket
- **Extensions:** external hooks/plugins first; WASM later
- **Distribution:** notarized DMG + Homebrew cask + Homebrew formula
- **License:** Apache-2.0

## Hard guardrails

### 1. Keep it terminal-first

Do not steer the project toward:

- browser-heavy shells
- webview-first architecture
- AI-first product positioning
- monolithic “do everything” core behavior

AI integrations are allowed.
AI-first product design is not the goal.

### 2. Protect the terminal bridge boundary

`libghostty` is an unstable upstream dependency and must be wrapped behind a narrow internal boundary.

Agents should:

- avoid spreading `libghostty` types across the repo
- prefer OpenMUX-native types like workspaces, panes, tabs, sessions, hooks, notifications, and keymaps
- keep upstream-specific details localized

### 3. Treat keyboard correctness as a core requirement

Input handling is not polish.
It is a blocker-level product concern.

Be careful around:

- EU/ISO layouts
- Alt/Option behavior
- right-Option semantics
- dead keys
- compose keys
- text input and IME integration

When a change touches input, keybindings, terminal encoding, or editor/meta behavior, explicitly account for these cases.

### 4. Protect packaged app resource loading

OpenMUX is distributed as a manually assembled macOS `.app` bundle, not an Xcode archive.
Swift Package Manager resource accessors can embed absolute build paths that work locally but fail for downloaded release assets.

When adding bundled resources, `Bundle.module` usage, app bundle layout changes, release assets, signing, or update/install behavior:

- verify resources resolve from the packaged `.app` layout, especially `Contents/Resources`
- do not rely on SwiftPM's local `.build` fallback paths for shipped app behavior
- update and run the packaged release smoke test so CI launches the archived app with local build resource bundles hidden

### 5. Prefer hooks and extension points over core bloat

If a feature can be expressed as a hook, plugin contract, or extension point without harming usability, prefer that over hardcoding the behavior into the core.

OpenMUX should make things **buildable**, not attempt to ship every workflow itself.

### 6. Keep it AI-friendly, not AI-shaped

OpenMUX should be easy for AI systems to work with because it uses good engineering discipline:

- explicit contracts
- strong typing
- documented extension points
- predictable structure
- spec-driven planning

Do not distort the product around agent-centric workflows just to satisfy tooling.

## Clean-room and licensing rules

OpenMUX is Apache-2.0 licensed.

The project may take **architectural inspiration** from tools like cmux, but agents must **not copy code or file contents** from GPL projects into this repository.

Allowed:

- using public behavior as inspiration
- reusing high-level requirements
- studying architecture and scope

Not allowed:

- copying implementation code
- copying source files or large chunks of text
- reproducing GPL project structure verbatim without justification

## Preferred engineering style

- Prefer small, composable modules over large rigid systems.
- Prefer explicit interfaces over hidden magic.
- Prefer boring, native, inspectable solutions over clever abstractions.
- Prefer stable contracts over incidental coupling.
- Prefer performance-safe defaults.
- Prefer documentation and specification when introducing new boundaries.

## Working guidance for agents

When proposing or implementing changes:

1. Check that the change makes the terminal **more powerful, more flexible, or more open**.
2. Preserve the boundary between product logic and the terminal engine bridge.
3. Call out effects on hooks, plugin APIs, CLI contracts, RPC, persistence, and key handling.
4. Keep AI-related features aligned with the “AI-friendly, not AI-first” rule.
5. Avoid speculative complexity when a smaller composable design works.

## If the repo is still sparse

This repository is still at an early foundation stage.

When code or structure is missing:

- do not invent a browser-heavy or cross-platform-first direction
- do not assume a Mac App Store target
- do not assume in-process plugin execution is the first step
- do prefer scaffolding that supports the documented architecture direction

## Deliverable bias

Good contributions for OpenMUX usually improve one or more of these:

- terminal fidelity
- keyboard correctness
- workspace/session model clarity
- extension/hook boundaries
- CLI/RPC clarity
- performance
- inspectability
- maintainability

If a change does not clearly help one of those, reconsider it.
