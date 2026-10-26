.PHONY: help generate run run-mac iphone ipad watch format format-check lint imports test-mac test-ios test-ipad test-ios-ipad test-apple relay-install relay-test relay-typecheck relay-dry-run relay-ci test gate

help:
	@printf '%s\n' \
		'generate       Generate the ignored Xcode project' \
		'run-mac        Build and open the Mac collector (Development, live sources)' \
		'iphone         Build the iPhone app for the reference simulator' \
		'ipad           Build the iPad app for the reference simulator' \
		'watch          Build the Watch app for the reference simulator' \
		'format         Format maintained Swift sources in place' \
		'format-check   Check Swift formatting' \
		'lint           Run strict SwiftLint' \
		'imports        Check Swift module import boundaries' \
		'test-mac       Run macOS tests' \
		'test-ios       Run iPhone 17 Pro Max iOS 26.1 tests' \
		'test-ipad      Run iPad Air 11-inch (M2) iOS 26.1 tests' \
		'test-ios-ipad  Build once and run the iPhone and iPad tests concurrently' \
		'relay-install  Install the relay dependencies from its lockfile' \
		'relay-test     Run relay tests' \
		'relay-typecheck Run relay TypeScript checks' \
		'relay-dry-run  Validate the relay deployment without contacting Cloudflare' \
		'relay-ci       Run all relay checks' \
		'test-apple     Run the macOS tests, then the iPhone and iPad tests' \
		'test           Run the Apple tests beside the relay tests' \
		'gate           Run the complete contribution-guide gate'

generate:
	Scripts/generate-project.sh

run: run-mac

run-mac: generate
	@xcodebuild -quiet build -scheme ResetRadarMac -configuration Development \
		-destination 'platform=macOS' -derivedDataPath .build/mac-run
	@open .build/mac-run/Build/Products/Development/ResetRadarMac.app

IPHONE_DESTINATION := platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.1
IPAD_DESTINATION := platform=iOS Simulator,name=iPad Air 11-inch (M2),OS=26.1
WATCH_DESTINATION := platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)

iphone: generate
	@xcodebuild -quiet build -scheme ResetRadar -configuration Development \
		-destination '$(IPHONE_DESTINATION)'

ipad: generate
	@xcodebuild -quiet build -scheme ResetRadar -configuration Development \
		-destination '$(IPAD_DESTINATION)'

watch: generate
	@xcodebuild -quiet build -scheme ResetRadarWatch -configuration Development \
		-destination '$(WATCH_DESTINATION)'

format:
	swift-format format --in-place --recursive $$(tr '\n' ' ' < Scripts/swift-roots.txt)

format-check:
	Scripts/lint-swift-format.sh

lint:
	swiftlint --strict

imports:
	Scripts/check-imports.sh

mac-arch-check: generate
	Scripts/check-mac-architecture.sh

test-mac:
	@xcodebuild -quiet test -scheme ResetRadarMac -destination 'platform=macOS'

test-ios:
	@xcodebuild -quiet test -scheme ResetRadar -destination '$(IPHONE_DESTINATION)'

test-ipad:
	@xcodebuild -quiet test -scheme ResetRadar -destination '$(IPAD_DESTINATION)'

# One invocation builds once and tests both simulators concurrently, so the run takes about as
# long as the slower destination rather than the sum of both.
test-ios-ipad:
	@xcodebuild -quiet test -scheme ResetRadar \
		-destination '$(IPHONE_DESTINATION)' -destination '$(IPAD_DESTINATION)'

relay-install:
	npm --prefix relay ci

relay-test:
	@npm --prefix relay --silent test

relay-typecheck:
	npm --prefix relay run typecheck

relay-dry-run:
	npm --prefix relay run deploy:dry-run

relay-ci: relay-install relay-test relay-typecheck relay-dry-run

# The Mac and iOS runs share one build database, so they run in sequence beside the relay tests.
test-apple:
	@$(MAKE) --no-print-directory test-mac
	@$(MAKE) --no-print-directory test-ios-ipad

test:
	+@$(MAKE) --no-print-directory -j2 test-apple relay-test

gate: generate format-check lint imports mac-arch-check test-mac test-ios-ipad relay-ci
