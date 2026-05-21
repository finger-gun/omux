.PHONY: help setup build-ghostty build test verify smoke smoke-packaged-release smoke-release-installer import-themes publish-unsigned package-release install-local-release tag-release uninstall-local dev app cli-help check-xcodegen generate-xcodeproj ui-test power-profile

SWIFT := env CLANG_MODULE_CACHE_PATH=.build/module-cache swift

help:
	@printf "OpenMUX development commands\n\n"
	@printf "  make setup         Build the vendored Ghostty runtime artifact\n"
	@printf "  make build-ghostty Same as setup\n"
	@printf "  make build         Build Swift packages and app\n"
	@printf "  make test          Run the Swift test suite\n"
	@printf "  make verify        Run build and test\n"
	@printf "  make smoke         Launch and sample OpenMUXApp as a smoke test\n"
	@printf "  make power-profile Capture a shareable OpenMUX runtime profile\n"
	@printf "  make smoke-packaged-release Launch packaged release app with build resources hidden\n"
	@printf "  make smoke-release-installer Run the packaged release installer smoke test\n"
	@printf "  make import-themes Import selected iTerm2 Color Schemes into bundled themes\n"
	@printf "  make publish-unsigned Build dist/OpenMUX.app (unsigned)\n"
	@printf "  make package-release Build GitHub Release assets under dist/release/ using VERSION\n"
	@printf "  make install-local-release Package, install to /Applications, and relaunch locally\n"
	@printf "  make tag-release     Create and push v$$(cat VERSION) from committed VERSION/CHANGELOG\n"
	@printf "  make uninstall-local Remove local OpenMUX installs and user data (prompts first)\n"
	@printf "  make dev           Launch OpenMUXApp\n"
	@printf "  make app           Launch OpenMUXApp\n"
	@printf "  make cli-help      Show omux CLI help\n"
	@printf "  make generate-xcodeproj Regenerate OpenMUX.xcodeproj from project.yml (requires xcodegen)\n"
	@printf "  make ui-test       Run the XCUIAutomation GUI test suite via xcodebuild\n"

setup: build-ghostty

build-ghostty:
	./Scripts/build-ghostty.sh

build:
	$(SWIFT) build

test:
	$(SWIFT) test

verify: build test

smoke:
	./Scripts/smoke-openmux-app.sh

power-profile:
	@status=0; \
	./Scripts/capture-openmux-power-profile.sh || status=$$?; \
	if [ "$$status" -ne 0 ] && [ "$$status" -ne 130 ]; then \
		exit "$$status"; \
	fi

smoke-packaged-release:
	./Scripts/smoke-packaged-release-app.sh

smoke-release-installer:
	./Scripts/smoke-release-installer.sh

import-themes:
	./Scripts/import-iterm2-themes.sh

publish-unsigned:
	./Scripts/publish-unsigned.sh

package-release:
	./Scripts/package-release.sh

install-local-release:
	./Scripts/install-local-release.sh

tag-release:
	./Scripts/tag-release.sh

uninstall-local:
	./Scripts/uninstall-local.sh

dev:
	GHOSTTY_RESOURCES_DIR="$(CURDIR)/Vendor/ghostty/zig-out/share/ghostty" $(SWIFT) run OpenMUXApp

app: dev

cli-help:
	$(SWIFT) run omux help

check-xcodegen:
	@command -v xcodegen >/dev/null 2>&1 || { \
		printf "xcodegen is required to generate OpenMUX.xcodeproj.\n"; \
		printf "Install it with: brew install xcodegen\n"; \
		exit 1; \
	}

generate-xcodeproj: check-xcodegen
	xcodegen generate --spec project.yml

ui-test: generate-xcodeproj build
	rm -rf .build/ui-test-results.xcresult .build/UITestApp
	./Scripts/wrap-app-for-uitest.sh
	xcodebuild test \
		-project OpenMUX.xcodeproj \
		-scheme OmuxUITests \
		-destination "platform=macOS" \
		-resultBundlePath .build/ui-test-results.xcresult \
		$(if $(UI_TEST),-only-testing OmuxUITests/$(UI_TEST))
