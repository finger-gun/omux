.PHONY: help setup build-ghostty build test verify smoke dev app cli-help

help:
	@printf "OpenMUX development commands\n\n"
	@printf "  make setup         Build the vendored Ghostty runtime artifact\n"
	@printf "  make build-ghostty Same as setup\n"
	@printf "  make build         Build Swift packages and app\n"
	@printf "  make test          Run the Swift test suite\n"
	@printf "  make verify        Run build and test\n"
	@printf "  make smoke         Launch and sample OpenMUXApp as a smoke test\n"
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

dev:
	swift run OpenMUXApp

app: dev

cli-help:
	swift run omux help
