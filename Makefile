.PHONY: help generate format format-check lint imports test-mac relay-install relay-test relay-typecheck relay-dry-run relay-ci test gate

help:
	@printf '%s\n' \
		'generate       Generate the ignored Xcode project' \
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
		'test           Run the macOS and relay tests' \
		'gate           Run the complete contribution-guide gate'

generate:
	Scripts/generate-project.sh

format:
	swift-format format --in-place --recursive $$(tr '\n' ' ' < Scripts/swift-roots.txt)

format-check:
	Scripts/lint-swift-format.sh

lint:
	swiftlint --strict

imports:
	Scripts/check-imports.sh

test-mac:
	xcodebuild test -scheme ResetRadarMac -destination 'platform=macOS'

relay-install:
	npm --prefix relay ci

relay-test:
	npm --prefix relay test

relay-typecheck:
	npm --prefix relay run typecheck

relay-dry-run:
	npm --prefix relay run deploy:dry-run

relay-ci: relay-install relay-test relay-typecheck relay-dry-run

test: test-mac relay-test

gate: generate format-check lint imports test-mac relay-ci
