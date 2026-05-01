.PHONY: help setup build-ghostty build test verify smoke import-themes publish-unsigned package-release dev app cli-help

help:
	@printf "OpenMUX development commands\n\n"
	@printf "  make setup         Build the vendored Ghostty runtime artifact\n"
	@printf "  make build-ghostty Same as setup\n"
	@printf "  make build         Build Swift packages and app\n"
	@printf "  make test          Run the Swift test suite\n"
	@printf "  make verify        Run build and test\n"
	@printf "  make smoke         Launch and sample OpenMUXApp as a smoke test\n"
	@printf "  make import-themes Import selected iTerm2 Color Schemes into bundled themes\n"
	@printf "  make publish-unsigned Build dist/OpenMUX.app (unsigned)\n"
	@printf "  make package-release RELEASE_VERSION=X.Y.Z Build GitHub Release assets under dist/release/\n"
	@printf "  make dev           Launch OpenMUXApp\n"
	@printf "  make app           Launch OpenMUXApp\n"
	@printf "  make cli-help      Show omux CLI help\n"

setup: build-ghostty

build-ghostty:
	./Scripts/build-ghostty.sh

build:
	swift build

test:
	swift test

verify: build test

smoke:
	./Scripts/smoke-openmux-app.sh

import-themes:
	./Scripts/import-iterm2-themes.sh

publish-unsigned:
	./Scripts/publish-unsigned.sh

package-release:
	@if [ -z "$(RELEASE_VERSION)" ]; then \
		printf 'error: RELEASE_VERSION is required\n' >&2; \
		exit 1; \
	fi
	./Scripts/package-release.sh

dev:
	swift run OpenMUXApp

app: dev

cli-help:
	swift run omux help
