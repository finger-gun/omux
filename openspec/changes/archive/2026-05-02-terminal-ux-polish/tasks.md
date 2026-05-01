## 1. Theme Picker Viewport

- [x] 1.1 Extract a testable viewport calculation for the interactive theme picker.
- [x] 1.2 Measure terminal height and render only the visible theme range.
- [x] 1.3 Add regression tests for selected-row visibility with more themes than rows.

## 2. Terminal Drag/Drop Paste

- [x] 2.1 Add shell-safe path formatting for dropped file URLs.
- [x] 2.2 Register runtime terminal views for file URL drops and route accepted drops to terminal text input.
- [x] 2.3 Add regression tests for dropped path formatting and terminal text routing where possible.

## 3. Command-Arrow Navigation

- [x] 3.1 Add narrow Command-Left and Command-Right terminal navigation handling.
- [x] 3.2 Preserve existing Command shortcut routing and Option/right-Option text behavior.
- [x] 3.3 Add regression tests for command-arrow navigation and shortcut preservation.

## 4. Native Titlebar Zoom

- [x] 4.1 Restore native double-click zoom/maximize behavior for the transparent workspace titlebar region.
- [x] 4.2 Add regression coverage for the workspace window titlebar behavior/configuration where possible.

## 5. Validation

- [x] 5.1 Run focused CLI, terminal bridge, core, and app shell tests.
- [x] 5.2 Run full Swift test suite and strict OpenSpec validation.
