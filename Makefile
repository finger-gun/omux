.PHONY: help setup build-ghostty build test verify smoke smoke-packaged-release import-themes publish-unsigned package-release uninstall-local dev app cli-help

help:
	@printf "OpenMUX development commands\n\n"
	@printf "  make setup         Build the vendored Ghostty runtime artifact\n"
	@printf "  make build-ghostty Same as setup\n"
	@printf "  make build         Build Swift packages and app\n"
	@printf "  make test          Run the Swift test suite\n"
	@printf "  make verify        Run build and test\n"
	@printf "  make smoke         Launch and sample OpenMUXApp as a smoke test\n"
	@printf "  make smoke-packaged-release Launch packaged release app with build resources hidden\n"
	@printf "  make import-themes Import selected iTerm2 Color Schemes into bundled themes\n"
	@printf "  make publish-unsigned Build dist/OpenMUX.app (unsigned)\n"
	@printf "  make package-release Build GitHub Release assets under dist/release/ using VERSION\n"
	@printf "  make uninstall-local Remove local OpenMUX installs and user data (prompts first)\n"
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

smoke-packaged-release:
	./Scripts/smoke-packaged-release-app.sh

import-themes:
	./Scripts/import-iterm2-themes.sh

publish-unsigned:
	./Scripts/publish-unsigned.sh

package-release:
	./Scripts/package-release.sh

uninstall-local:
	./Scripts/uninstall-local.sh

dev:
	GHOSTTY_RESOURCES_DIR="$(CURDIR)/Vendor/ghostty/zig-out/share/ghostty" swift run OpenMUXApp

app: dev

cli-help:
	swift run omux help
