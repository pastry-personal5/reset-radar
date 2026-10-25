.PHONY: help generate run run-mac format format-check lint imports test-mac relay-install relay-test relay-typecheck relay-dry-run relay-ci test gate

help:
	@printf '%s\n' \
		'generate       Generate the ignored Xcode project' \
		'run-mac        Build and open the Mac collector (Development, live sources)' \
		'format         Format maintained Swift sources in place' \
		'format-check   Check Swift formatting' \
		'lint           Run strict SwiftLint' \
		'imports        Check Swift module import boundaries' \
		'test-mac       Run macOS tests' \
		'relay-install  Install the relay dependencies from its lockfile' \
		'relay-test     Run relay tests' \
		'relay-typecheck Run relay TypeScript checks' \
		'relay-dry-run  Validate the relay deployment without contacting Cloudflare' \
		'relay-ci       Run all relay checks' \
		'test           Run the macOS and relay tests concurrently' \
		'gate           Run the complete contribution-guide gate'

generate:
	Scripts/generate-project.sh

run: run-mac

run-mac: generate
	@xcodebuild -quiet build -scheme ResetRadarMac -configuration Development \
		-destination 'platform=macOS' -derivedDataPath .build/mac-run
	@open .build/mac-run/Build/Products/Development/ResetRadarMac.app

format:
	swift-format format --in-place --recursive $$(tr '\n' ' ' < Scripts/swift-roots.txt)

format-check:
	Scripts/lint-swift-format.sh

lint:
	swiftlint --strict

imports:
	Scripts/check-imports.sh

test-mac:
	@xcodebuild -quiet test -scheme ResetRadarMac -destination 'platform=macOS'

relay-install:
	npm --prefix relay ci

relay-test:
	@npm --prefix relay --silent test

relay-typecheck:
	npm --prefix relay run typecheck

relay-dry-run:
	npm --prefix relay run deploy:dry-run

relay-ci: relay-install relay-test relay-typecheck relay-dry-run

test:
	+@$(MAKE) --no-print-directory -j2 test-mac relay-test

gate: generate format-check lint imports test-mac relay-ci
