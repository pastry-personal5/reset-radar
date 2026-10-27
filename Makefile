.PHONY: help generate run run-mac iphone ipad watch ipa format format-check lint imports mac-arch-check test-mac test-ios test-ipad test-ios-ipad test-watch test-apple relay-install relay-test relay-typecheck relay-dry-run relay-ci test gate

help:
	@printf '%s\n' \
		'generate       Generate the ignored Xcode project' \
		'run-mac        Build and open the Mac collector (Development, live sources)' \
		'iphone         Build the iPhone app for the reference simulator' \
		'ipad           Build the iPad app for the reference simulator' \
		'watch          Build the Watch app for the reference simulator' \
		'ipa            Create .build/ipa/ResetRadar.ipa if it is absent' \
		'format         Format maintained Swift sources in place' \
		'format-check   Check Swift formatting' \
		'lint           Run strict SwiftLint' \
		'imports        Check Swift module import boundaries' \
		'mac-arch-check Verify Release Mac binaries are arm64-only' \
		'test-mac       Run macOS tests' \
		'test-ios       Run iPhone 17 Pro Max iOS 26.1 tests' \
		'test-ipad      Run iPad Air 11-inch (M2) iOS 26.1 tests' \
		'test-ios-ipad  Build once and run the iPhone and iPad tests concurrently' \
		'test-watch     Run the Watch tests on the reference simulator' \
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
IPA_PACKAGE := .build/ipa/ResetRadar.ipa
MAC_TEST_DERIVED_DATA := .build/derived-data/mac-tests
IOS_DERIVED_DATA := .build/derived-data/ios
WATCH_DERIVED_DATA := .build/derived-data/watch

iphone: generate
	@xcodebuild -quiet build -scheme ResetRadar -configuration Development \
		-destination '$(IPHONE_DESTINATION)' -derivedDataPath '$(IOS_DERIVED_DATA)'

ipad: generate
	@xcodebuild -quiet build -scheme ResetRadar -configuration Development \
		-destination '$(IPAD_DESTINATION)' -derivedDataPath '$(IOS_DERIVED_DATA)'

watch: generate
	@xcodebuild -quiet build -scheme ResetRadarWatch -configuration Development \
		-destination '$(WATCH_DESTINATION)' -derivedDataPath '$(WATCH_DERIVED_DATA)'

# The package is signed with the owner's local Personal Team configuration.  It intentionally
# preserves an existing IPA so a repeat `make ipa` cannot replace a package awaiting installation.
ipa: generate
	@set -eu; \
	package_path='$(IPA_PACKAGE)'; \
	if [ -e "$$package_path" ]; then \
		printf '%s\n' "IPA already exists: $$package_path"; \
	else \
		workdir=$$(mktemp -d /private/tmp/reset-radar-ipa.XXXXXX); \
		trap 'rm -rf "$$workdir"' EXIT; \
		xcodebuild -quiet archive \
			-project ResetRadar.xcodeproj -scheme ResetRadar -configuration Release \
			-destination 'generic/platform=iOS' \
			-archivePath "$$workdir/ResetRadar.xcarchive" -allowProvisioningUpdates; \
		archive_app="$$workdir/ResetRadar.xcarchive/Products/Applications/ResetRadar.app"; \
		codesign --verify --deep --strict "$$archive_app"; \
		mkdir -p "$$workdir/Payload"; \
		ditto "$$archive_app" "$$workdir/Payload/ResetRadar.app"; \
		ditto -c -k --sequesterRsrc --keepParent "$$workdir/Payload" "$$workdir/ResetRadar.ipa"; \
		mkdir -p "$$(dirname "$$package_path")"; \
		cp "$$workdir/ResetRadar.ipa" "$$package_path"; \
		printf '%s\n' "Created IPA: $$package_path"; \
	fi

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
	@xcodebuild -quiet test -scheme ResetRadarMac -destination 'platform=macOS' \
		-derivedDataPath '$(MAC_TEST_DERIVED_DATA)'

test-ios:
	@xcodebuild -quiet test -scheme ResetRadar -destination '$(IPHONE_DESTINATION)' \
		-derivedDataPath '$(IOS_DERIVED_DATA)'

test-ipad:
	@xcodebuild -quiet test -scheme ResetRadar -destination '$(IPAD_DESTINATION)' \
		-derivedDataPath '$(IOS_DERIVED_DATA)'

# One invocation builds once and tests both simulators concurrently, so the run takes about as
# long as the slower destination rather than the sum of both.
test-ios-ipad:
	@xcodebuild -quiet test -scheme ResetRadar \
		-destination '$(IPHONE_DESTINATION)' -destination '$(IPAD_DESTINATION)' \
		-derivedDataPath '$(IOS_DERIVED_DATA)'

test-watch:
	@xcodebuild -quiet test -scheme ResetRadarWatch -destination '$(WATCH_DESTINATION)' \
		-derivedDataPath '$(WATCH_DERIVED_DATA)'

relay-install:
	npm --prefix relay ci

relay-test:
	@npm --prefix relay --silent test

relay-typecheck:
	npm --prefix relay run typecheck

relay-dry-run:
	npm --prefix relay run deploy:dry-run

relay-ci: relay-install relay-test relay-typecheck relay-dry-run

# The Apple runs share one build database, so they run in sequence beside the relay tests.
test-apple:
	@$(MAKE) --no-print-directory test-mac
	@$(MAKE) --no-print-directory test-ios-ipad
	@$(MAKE) --no-print-directory test-watch

test:
	+@$(MAKE) --no-print-directory -j2 test-apple relay-test

gate: generate format-check lint imports mac-arch-check test-mac test-ios-ipad test-watch relay-ci
