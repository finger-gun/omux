## Why

OpenMUX needs a deliberate foundation before feature work begins. Without clear boundaries for the native app shell, terminal bridge, input pipeline, control plane, and extension seams, later changes will couple directly to unstable upstream APIs and make the product harder to evolve, test, and extend.

Now is the right time to define that foundation because the project is still early, the manifesto is clear about terminal-first and hackable design, and the research already points to a concrete v1 direction: macOS-native, AppKit-first, libghostty-backed, JSON-RPC-controlled, and hookable by design.

## Goals

- Establish the core architectural contracts future changes can build on.
- Define the OpenMUX-native vocabulary for workspaces, tabs, panes, sessions, hooks, notifications, and key handling.
- Keep libghostty isolated behind a narrow bridge so the rest of the system does not depend directly on upstream internals.
- Define the local app/CLI control plane around `omux` and JSON-RPC over a Unix domain socket.
- Make keyboard correctness, especially ISO/EU layouts and right-Option behavior, part of the foundation rather than a later refinement.
- Create extension seams that support hooks and future plugins without bloating the core.

## Non-goals

- Shipping the full end-user workspace experience in this change.
- Implementing a full plugin SDK or WASM runtime.
- Building browser-heavy UI, webview-first architecture, or an AI-first product workflow.
- Targeting the Mac App Store in v1.
- Copying code or implementation details from GPL projects such as cmux.

## What Changes

- Define the native macOS application foundation for OpenMUX as an AppKit-first desktop shell with selective SwiftUI for non-terminal chrome.
- Define the terminal integration boundary so libghostty is consumed through a single narrow bridge module instead of leaking through the app.
- Define the normalized input pipeline from AppKit events to terminal/session behavior, including requirements for international keyboard correctness.
- Define the `omux` local control plane and RPC contract as the primary automation boundary between CLI and app.
- Define the initial hook and extension categories that make the system open and hackable without requiring an in-process plugin runtime.
- Define the initial module and responsibility split so future changes can land as focused OpenSpecs instead of broad architectural rewrites.
- Use clean-room behavioral inspiration only; no copied GPL code, structure, or implementation text.

## Capabilities

### New Capabilities
- `macos-app-shell`: Native desktop foundation for windows, workspaces, tabs, panes, focus, and shell-level responsibilities.
- `terminal-bridge`: Stable OpenMUX boundary around pinned libghostty integration, surface ownership, and session lifecycle.
- `input-pipeline`: Normalized keyboard and text-input handling with explicit international-layout and modifier requirements.
- `omux-control-plane`: Local CLI-to-app control model using `omux` and JSON-RPC over a Unix domain socket.
- `hooks-foundation`: Initial lifecycle, session, command, UI, and input hook contracts for extension without core bloat.

### Modified Capabilities

None.

## Impact

- Affects initial application architecture, module boundaries, and future repository structure.
- Establishes the core contracts later implementation changes must follow.
- Constrains terminal integration to a narrow libghostty bridge boundary.
- Introduces foundation requirements for keyboard/input correctness, CLI/RPC behavior, and extension seams.
- Influences future app, CLI, persistence, notifications, and plugin-related changes.
