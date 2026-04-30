## 1. Repository and module foundation

- [x] 1.1 Create the initial native app, CLI, and package/module scaffolding for the AppKit-first OpenMUX architecture.
- [x] 1.2 Define the OpenMUX-native core types for workspaces, tabs, panes, sessions, hooks, notifications, and normalized key events.
- [x] 1.3 Establish the module boundary that makes the terminal bridge the only layer allowed to depend directly on libghostty.

## 2. Terminal bridge foundation

- [x] 2.1 Add the pinned libghostty integration path and wrap it behind a narrow bridge interface.
- [x] 2.2 Implement bridge-owned terminal surface and session lifecycle coordination.
- [x] 2.3 Add bridge-facing tests or validation coverage that confirms app code consumes OpenMUX abstractions rather than raw libghostty APIs.

## 3. Native shell and input pipeline

- [x] 3.1 Implement the AppKit-first shell baseline for windows, workspace structure, pane hosting, and focus ownership.
- [x] 3.2 Implement the normalized input pipeline from AppKit events to OpenMUX key events before terminal or shortcut dispatch.
- [x] 3.3 Add validation coverage for ISO/EU layouts, Alt/Option behavior, right-Option-sensitive flows, dead keys, and compose-related behavior.

## 4. CLI and control plane

- [x] 4.1 Create the local JSON-RPC transport layer over a Unix domain socket between the app and `omux`.
- [x] 4.2 Define and implement the first capability-oriented `omux` operations around workspace/session control.
- [x] 4.3 Add validation coverage that exercises CLI-to-app calls through the public RPC boundary instead of private in-process coupling.

## 5. Hook seams and follow-on documentation

- [x] 5.1 Define the initial lifecycle, session, command, UI, and input hook contracts in OpenMUX-native terms.
- [x] 5.2 Implement the first external-hook-compatible execution path without introducing an in-process plugin runtime.
- [x] 5.3 Update repository and developer documentation so future changes build on the foundation contracts rather than bypassing them.
