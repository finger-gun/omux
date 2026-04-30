# Contributing to OpenMUX

Thanks for considering a contribution to **OpenMUX**.
This project is being built in the open, and contributions are welcome.

---

## Code of Conduct

By participating, you agree to follow our [Code of Conduct](./CODE_OF_CONDUCT.md).

---

## How to Contribute

You can help by:

* Reporting bugs via [issues](https://github.com/finger-gun/omux/issues)
* Proposing features and workflow improvements
* Improving documentation
* Submitting code changes

---

## Before You Open a Pull Request

* Keep changes focused and scoped.
* Explain the problem your change solves.
* Update documentation when behavior or project structure changes.
* Add or update tests when code changes affect behavior.

---

## Pull Requests

* Branch from `main`.
* Use clear commit messages that explain intent.
* Link related issues when relevant.
* Prefer small, reviewable pull requests over large batches of unrelated changes.

Example:

```bash
git checkout -b feature/my-change
```

---

## Project Direction

Before making large changes, read the [manifest](./docs/manifest.md).

OpenMUX values:

* A terminal-first experience
* Strong foundations over unnecessary reinvention
* Hookability and extension points over rigid built-in workflows
* Performance, sensible defaults, and international-friendly input handling

If a proposed change moves the project away from those principles, open an issue or draft PR first so the direction can be discussed early.

---

## Keyboard-sensitive changes

Keyboard correctness is a blocker-level product concern in OpenMUX.

When a change touches terminal input, keybindings, clipboard routing, pointer selection, terminal encoding, or IME/composition behavior:

* Preserve Ghostty-compatible `macos-option-as-alt` semantics for `false`, `true`, `left`, `right`, and unset/default if OpenMUX owns the user-facing setting.
* Do not hardcode layout-specific Option mappings; layout text must come from AppKit for the active keyboard layout.
* Add or update automated tests for sided modifiers, composition/preedit behavior, and command routing when behavior changes.
* Use this manual verification matrix when practical:
  * US layout
  * Swedish/Nordic ISO
  * At least one additional EU layout when available
  * At least one IME workflow covering preedit, candidate placement, commit, and cancellation

---

## Questions

If you are unsure about an approach, open an issue or a draft pull request early.
