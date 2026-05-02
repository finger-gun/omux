#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

cd "$ROOT_DIR"

latest_tag="${RELEASE_TAG:-}"
if [ -z "$latest_tag" ]; then
  latest_tag="$(git tag --list 'v[0-9]*' --sort=-v:refname | head -n 1 || true)"
fi

if [ -n "$latest_tag" ]; then
  if ! git rev-parse --verify --quiet "$latest_tag" >/dev/null; then
    echo "error: release tag '$latest_tag' does not exist" >&2
    exit 1
  fi

  base_label="$latest_tag"
  commit_range="$latest_tag..HEAD"
  commits="$(git log "$commit_range" --oneline --no-merges || true)"
  files="$(
    {
      git diff "$commit_range" --name-only
      git diff --cached --name-only
      git diff --name-only
      git ls-files --others --exclude-standard
    } | sort -u
  )"
else
  base_label="no previous v* tag"
  commits="$(git log --oneline --no-merges || true)"
  files="$(
    {
      git ls-files
      git ls-files --others --exclude-standard
    } | sort -u
  )"
fi

current_version="unknown"
if [ -f VERSION ]; then
  current_version="$(sed -n '1p' VERSION)"
fi

surface_for_path() {
  case "$1" in
    Sources/OmuxCLI/*) echo "CLI" ;;
    Sources/OmuxAppShell/*|Sources/OpenMUXApp/*) echo "App shell" ;;
    Sources/OmuxTerminalBridge/*|Sources/CGhostty/*) echo "Terminal bridge" ;;
    Sources/OmuxConfig/*) echo "Config" ;;
    Sources/OmuxHooks/*) echo "Hooks" ;;
    Sources/OmuxTheme/*) echo "Themes" ;;
    Sources/OmuxControlPlane/*) echo "Control plane" ;;
    Sources/OmuxCore/*) echo "Core model" ;;
    Tests/*) echo "Tests" ;;
    Scripts/*|Makefile|VERSION|CHANGELOG.md|.github/workflows/*|.github/release.yml) echo "Packaging/release" ;;
    .github/skills/*) echo "Agent skills" ;;
    docs/*|README.md) echo "Documentation" ;;
    openspec/*) echo "OpenSpec" ;;
    Vendor/ghostty/*) echo "Vendored Ghostty" ;;
    Package.swift|Package.resolved) echo "Swift package" ;;
    *) echo "Other" ;;
  esac
}

printf 'OpenMUX changes since release\n'
printf '=============================\n\n'
printf 'Current VERSION: %s\n' "$current_version"
printf 'Base: %s\n\n' "$base_label"

printf 'Commits\n'
printf '%s\n' '-------'
if [ -n "$commits" ]; then
  printf '%s\n' "$commits"
else
  printf 'No commits since base.\n'
fi

printf '\nChanged files by surface\n'
printf '%s\n' '------------------------'
if [ -n "$files" ]; then
  tmp_file="$(mktemp "${TMPDIR:-/tmp}/openmux-release-files.XXXXXX")"
  trap 'rm -f "$tmp_file"' EXIT INT TERM

  printf '%s\n' "$files" | while IFS= read -r path; do
    [ -n "$path" ] || continue
    printf '%s\t%s\n' "$(surface_for_path "$path")" "$path"
  done | sort > "$tmp_file"

  current_surface=""
  while IFS="$(printf '\t')" read -r surface path; do
    if [ "$surface" != "$current_surface" ]; then
      current_surface="$surface"
      printf '\n%s\n' "$surface"
    fi
    printf '  %s\n' "$path"
  done < "$tmp_file"
else
  printf 'No changed files since base.\n'
fi

printf '\nWorking tree\n'
printf '%s\n' '------------'
working_tree="$(git status --short || true)"
if [ -n "$working_tree" ]; then
  printf '%s\n' "$working_tree"
else
  printf 'Clean.\n'
fi
