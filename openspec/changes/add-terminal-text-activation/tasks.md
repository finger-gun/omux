## 1. Activation Model

- [x] 1.1 Add OpenMUX-native terminal text activation request/context types.
- [x] 1.2 Add token extraction and local path resolution helpers for visible terminal text.
- [x] 1.3 Add unit tests for token extraction and local path resolution.

## 2. Terminal Pointer Integration

- [x] 2.1 Thread an optional text activation callback from app shell through hosted terminal views to the runtime host view.
- [x] 2.2 Detect Command-click activation gestures while preserving plain pointer forwarding.
- [x] 2.3 Add bridge/runtime tests proving plain clicks still reach the terminal and handled activation clicks can be claimed.
- [x] 2.4 Add Command-hover pointer affordance for text the app can activate.

## 3. App Shell and Plugin Handling

- [x] 3.1 Emit an input hook named `terminal-text-activated` with token, cwd, modifiers, and resolved path payload fields.
- [x] 3.2 Open Markdown preview for activated readable `.md`/`.markdown` paths only when the bundled plugin is enabled.
- [x] 3.3 Add app-shell tests for enabled and disabled Markdown activation handling.
- [x] 3.4 Publish terminal text activation on the `omux events` stream.

## 4. Documentation and Validation

- [x] 4.1 Document terminal text activation gesture and hook payload.
- [x] 4.2 Validate Swift tests and OpenSpec changes.
