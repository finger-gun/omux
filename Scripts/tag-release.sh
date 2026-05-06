#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
REMOTE="${REMOTE:-origin}"
DRY_RUN="${DRY_RUN:-0}"

if [ ! -f "$VERSION_FILE" ]; then
  echo "error: missing VERSION file" >&2
  exit 1
fi

VERSION="$(sed -n '1p' "$VERSION_FILE" | tr -d '[:space:]')"
TAG="v$VERSION"

if ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "error: VERSION must contain MAJOR.MINOR.PATCH without a leading v" >&2
  exit 1
fi

"$ROOT_DIR/Scripts/extract-release-notes.sh" "$VERSION" >/dev/null

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "error: working tree has uncommitted changes; commit VERSION and CHANGELOG.md before tagging" >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "error: local tag $TAG already exists" >&2
  exit 1
fi

if git ls-remote --tags "$REMOTE" "refs/tags/$TAG" | grep -q .; then
  echo "error: remote tag $TAG already exists on $REMOTE" >&2
  exit 1
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "Would run: git tag $TAG"
  echo "Would run: git push $REMOTE $TAG"
  exit 0
fi

git tag "$TAG"
git push "$REMOTE" "$TAG"

printf 'Published release tag %s to %s\n' "$TAG" "$REMOTE"
