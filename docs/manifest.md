# OpenMUX Manifesto

## 1. Why OpenMUX exists

Terminals are the backbone of software development.

Yet modern terminal tools are increasingly:

* Opinionated toward specific vendors, agents, or workflows
* Bloated with features most developers do not need
* Difficult to extend without forking the whole project
* Too slow to fix the things that actually matter

OpenMUX exists to reclaim the terminal as:

> A fast, native, flexible, and hackable workspace for developers.

Not for one AI vendor.
Not for one workflow.
Not for hype cycles.

For people who build things.

---

## 2. Core Philosophy

### 2.1 Open by design

OpenMUX is not just open source.
It is open at its core.

Every part of the system should be:

* Inspectable
* Replaceable
* Extendable
* Scriptable

If something does not work for you, you should not need to fork the entire project.
You should be able to hook into it, override it, or replace it.

OpenMUX should be a platform for terminal workflows, not a closed box.

---

### 2.2 Terminal first

The terminal is the product.

Not AI.
Not a browser.
Not a dashboard.
Not a sidecar experience.

OpenMUX focuses on:

* Reliable terminal rendering via libghostty
* Fast input and output
* Stable long-running sessions
* Correct keyboard handling
* Native macOS behavior

Everything else is secondary.

---

### 2.3 Native where it matters

OpenMUX is a macOS application first.

That means:

* Native windows
* Native menus
* Native notifications
* Native keyboard handling
* Native accessibility expectations

The terminal surface should feel like it belongs on macOS.
The app should not be a web shell pretending to be native.

OpenMUX should use AppKit where precision matters and SwiftUI where it helps.

---

### 2.4 Built on strong foundations

Terminal rendering is hard.
We do not reinvent the hardest part.

OpenMUX builds on libghostty as the terminal engine.

libghostty should be treated as a powerful but carefully isolated dependency:

* Pinned intentionally
* Wrapped behind a narrow OpenMUX bridge
* Kept out of higher-level product logic

The rest of OpenMUX should speak in OpenMUX concepts:

* Workspaces
* Tabs
* Panes
* Sessions
* Hooks
* Plugins
* Notifications

---

### 2.5 Tools, not opinions

OpenMUX does not dictate your workflow.

It should work equally well for:

* Shell users
* tmux users
* SSH-heavy workflows
* Backend, frontend, and infrastructure engineers
* AI-assisted workflows
* Local scripts and custom automation

We provide primitives.
You build your workflow.

---

### 2.6 Hackability over features

We will always prefer:

> A small, composable system over a large, rigid one.

Instead of putting every feature directly into the core, OpenMUX should expose:

* Hooks
* Events
* Commands
* Extension points
* A local API

The goal is not to build everything.
The goal is to make everything buildable.

That includes terminal-engine upcalls: cwd changes, command completion, bell, URL-open requests, progress, and similar session signals should become OpenMUX-native events and structured hook payloads rather than leaking engine-owned enums or getting flattened to strings.

---

### 2.7 Sensible defaults

Power should not come at the cost of usability.

OpenMUX should feel good out of the box:

* Tabs for projects
* Split panes for workflows
* Clear session management
* Useful notifications
* Thoughtful keybindings
* Predictable restore behavior

You should not need to configure it for hours before it becomes useful.

---

### 2.8 International-first

Developers are global.

Keyboard handling must work for:

* EU layouts
* Alt/Option combinations
* Right Option / AltGr behavior
* Dead keys and compose keys
* Editors that rely on Meta/Alt shortcuts

Broken input is not a minor bug.
It is a blocker.

OpenMUX treats correct input handling as a core feature, not an edge case.

---

## 3. AI Philosophy

OpenMUX should be AI-friendly.
But it should not be AI-first.

AI agents should integrate through the same open system as every other tool:

* CLI commands
* JSON-RPC
* Hooks
* Events
* External plugins

No agent should be privileged in the core.
Claude, Codex, Aider, local models, shell scripts, and future tools should all be peers.

The same rule applies to configuration and appearance: users configure **OpenMUX**, and OpenMUX configures the terminal engine. Themes, font choices, terminal defaults, and future UX-facing settings should live in OpenMUX-native config and be compiled to Ghostty internally instead of exposing Ghostty config as the product surface.

The right architecture is not:

> A terminal with one AI baked in.

It is:

> A programmable terminal workspace where AI is one powerful kind of plugin.

---

## 4. The OpenMUX Control Plane

OpenMUX should be controllable from outside the UI.

A companion CLI named `omux` should allow users and tools to control the running app:

* Open a project
* Create a tab
* Split a pane
* Run a command
* Focus a session
* List workspaces
* Send a notification
* Restore a layout

The CLI is not a second terminal emulator.
It is a remote control for the app.

The app and CLI should communicate over a local protocol, starting with JSON-RPC over a Unix domain socket.

This makes OpenMUX:

* Scriptable
* Automatable
* Debuggable
* Tool-friendly
* Agent-friendly

---

## 5. Hooks and Plugins

OpenMUX should be hookable from day one.

Core events should include:

* App started
* Workspace opened
* Tab created
* Pane focused
* Command started
* Command finished
* Command failed
* Terminal output matched a rule
* Notification raised

External tools should be able to subscribe to events and send commands back to OpenMUX.

The first plugin model should be simple and robust:

* External processes
* JSON-RPC messages
* Clear schemas
* Explicit capabilities

Over time, OpenMUX can add first-class runtimes for plugin authors:

* TypeScript via Deno
* Sandboxed plugins via WebAssembly
* Native plugins where appropriate

But the plugin system should not depend on one language.
The protocol is the platform.

---

## 6. What OpenMUX is NOT

OpenMUX is not:

* An AI-first terminal
* A browser inside a terminal
* A Claude-specific workflow tool
* A monolithic do-everything app
* A web app wrapped as a desktop app
* A fork of cmux
* A fork of Ghostty

OpenMUX is a clean-room project inspired by good ideas, built on permissive foundations.

---

## 7. Architecture Principles

### 7.1 AppKit-first macOS app

OpenMUX should be a real macOS app.

The app shell should be AppKit-first, with SwiftUI used selectively for areas where it makes sense, such as settings, onboarding, and non-terminal UI.

Precision areas such as terminal input, focus, panes, keyboard events, and accessibility should remain native and explicit.

---

### 7.2 Thin libghostty bridge

Only one narrow layer should talk directly to libghostty.

That layer should translate between:

* Ghostty concepts
* OpenMUX concepts

The rest of the app should not depend on libghostty internals.

This protects OpenMUX from upstream churn and keeps the architecture understandable.

---

### 7.3 Local-first API

OpenMUX should expose a local API before it exposes a plugin marketplace.

The first API should be simple:

* JSON-RPC 2.0
* Unix domain socket
* Request/response commands
* Fire-and-forget events

This gives the CLI, plugins, scripts, and agents one shared control plane.

---

### 7.4 External plugins first

Plugins should start out as external processes.

This gives us:

* Crash isolation
* Language freedom
* Easier debugging
* Less runtime complexity

A plugin should be able to be written in any language as long as it can speak the OpenMUX protocol.

---

### 7.5 Runtime choices are optional

Deno, Lua, Node, and WebAssembly are not the plugin system.

They are possible runtimes for plugins.

The long-term direction should be:

* External JSON-RPC plugins first
* TypeScript/Deno support when useful
* WebAssembly for sandboxed plugins later
* Avoid embedding Node as a core dependency

OpenMUX should not lock the ecosystem to one runtime.

---

### 7.6 Performance is a feature

OpenMUX should be fast by default:

* Fast startup
* Low memory overhead
* Smooth rendering
* No unnecessary background processes
* No browser engine unless there is a very strong reason

If something slows the terminal down, it does not belong in the core.

---

## 8. Licensing Philosophy

OpenMUX should use a permissive license.

The preferred license is Apache-2.0.

This ensures:

* Anyone can build on it
* Companies can adopt it without friction
* Contributors get clearer patent protection
* The ecosystem can grow freely

We believe openness should enable usage, not restrict it.

OpenMUX should avoid copying GPL code from cmux.
Ideas can inspire us.
Code should not be copied.

---

## 9. V1 Product Direction

The first useful version of OpenMUX should focus on the essentials:

* Native macOS app
* libghostty-backed terminal surfaces
* Tabs
* Split panes
* Project workspaces
* Session persistence
* Notifications
* Correct EU keyboard support
* `omux` CLI
* JSON-RPC local control plane
* External hook/plugin support

Things that should not be in v1:

* Embedded browser
* AI vendor lock-in
* Plugin marketplace
* Mac App Store distribution
* Overbuilt runtime system

V1 should prove the foundation.
Not the entire vision.

---

## 10. Long-Term Vision

OpenMUX aims to become:

> The open foundation for modern terminal workspaces.

Not by locking users in,
but by being:

* Native
* Reliable
* Extensible
* Scriptable
* Agent-friendly
* Human-first

OpenMUX should become the place where terminals, tools, scripts, and agents can cooperate without giving up user control.

---

## 11. Guiding Principle

At every decision point, we ask:

> Does this make the terminal more powerful, more flexible, and more open?

And also:

> Does this serve developers first?

If the answer is no,
we do not ship it.

---

## 12. Final Words

OpenMUX is built for developers who:

* Care about their tools
* Want control over their workflow
* Prefer systems they can understand and modify
* Believe the terminal should be programmable
* Want AI to integrate without taking over

This is not a finished product.

It is a foundation.

Build on it.
