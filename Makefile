SHELL := /bin/bash

.DEFAULT_GOAL := help

.PHONY: help status engine-status bump-api-version swift-test engine-test test build-release package app app-info run-app dev-check release-check

help: ## Show available development and release commands
	@printf "RVC-WebUI-MacOS command index\n\n"
	@printf "Status:\n"
	@printf "  %-16s %s\n" "make status" "Show root repository status"
	@printf "  %-16s %s\n" "make engine-status" "Show nested engine repository status"
	@printf "\nValidation:\n"
	@printf "  %-16s %s\n" "make swift-test" "Run Swift client tests"
	@printf "  %-16s %s\n" "make engine-test" "Run focused Python engine regression tests"
	@printf "  %-16s %s\n" "make dev-check" "Run the shared development validation gate"
	@printf "  %-16s %s\n" "make release-check" "Run the local release gate and verify the app bundle"
	@printf "\nBuild:\n"
	@printf "  %-16s %s\n" "make bump-api-version" "Bump backend API/build version and sync the client constant"
	@printf "  %-16s %s\n" "make build-release" "Build the Swift client release executable"
	@printf "  %-16s %s\n" "make package" "Build dist/SwiftRVCMacClient.app and print app summary"
	@printf "  %-16s %s\n" "make app-info" "Print packaged app metadata and size summary"
	@printf "  %-16s %s\n" "make run-app" "Launch dist/SwiftRVCMacClient.app for local verification"
	@printf "\nCommon flows:\n"
	@printf "  %-16s %s\n" "feature check" "make dev-check"
	@printf "  %-16s %s\n" "package app" "make package"
	@printf "  %-16s %s\n" "release gate" "make release-check"

status: ## Show root repository status
	git status --short

engine-status: ## Show nested engine repository status
	git -C engine status --short

bump-api-version: ## Bump backend API/build version and sync the client compatibility constant
	./scripts/bump-backend-api-version.py

swift-test: ## Run Swift client tests
	cd mac-client && swift test

engine-test: ## Run focused Python engine regression tests
	./engine/.venv/bin/python -m unittest engine.tests.test_operation_state engine.tests.test_realtime_vc

test: dev-check ## Run the standard local validation gate

build-release: ## Build the Swift client release executable
	./scripts/bump-backend-api-version.py >/dev/null
	cd mac-client && swift build -c release

package: ## Build the packaged macOS app into dist/
	bash scripts/build-macos-app.sh
	bash scripts/app-info.sh

app: package ## Alias for package

app-info: ## Show packaged app metadata and size summary
	bash scripts/app-info.sh

run-app: ## Launch the packaged app from dist/ for local verification
	@if [[ ! -d "dist/SwiftRVCMacClient.app" ]]; then \
		echo "missing app bundle: dist/SwiftRVCMacClient.app" >&2; \
		echo "run 'make package' first" >&2; \
		exit 1; \
	fi
	open -n dist/SwiftRVCMacClient.app

dev-check: ## Run the shared development validation script
	bash scripts/dev-check.sh

release-check: ## Run the local release gate and verify the app bundle
	bash scripts/release-check.sh
