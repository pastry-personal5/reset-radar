.PHONY: help generate run dev-mac dev-iphone dev-ipad dev-watch rel-ipa rel-mac-package \
	rel-mac-install format check-format lint check-imports check-mac-arch check-simulators \
	test-scripts test-mac test-iphone test-ipad test-iphone-ipad test-watch test-apple \
	relay-install relay-test relay-typecheck relay-dry-run relay-ci test gate

# Also applies to multiple goals (make -j dev-iphone dev-ipad) and inherited MAKEFLAGS.
.NOTPARALLEL:

help:
	@printf '%s\n' \
		'Setup' \
		'  generate          Generate the ignored Xcode project' \
		'Development builds (Development configuration)' \
		'  dev-mac           Build and open the Mac collector with live sources (alias: run)' \
		'  dev-iphone        Build the iPhone app for the reference simulator' \
		'  dev-ipad          Build the iPad app for the reference simulator' \
		'  dev-watch         Build the Watch app for the reference simulator' \
		'Release artifacts (signed Release configuration)' \
		'  rel-ipa           Create .build/ipa/ResetRadar.ipa if it is absent' \
		'  rel-mac-package   Create .build/mac/ResetRadarMac.zip if it is absent' \
		'  rel-mac-install   Build fresh and install to /Applications with the rr launcher' \
		'Formatting and checks' \
		'  format            Format maintained Swift sources in place' \
		'  check-format      Check Swift formatting' \
		'  lint              Run strict SwiftLint' \
		'  check-imports     Check Swift module import boundaries' \
		'  check-mac-arch    Verify unsigned Release Mac binaries are arm64-only' \
		'  check-simulators  Check host CoreSimulator service access' \
		'Tests' \
		'  test-scripts      Run the build-script regression tests (timeouts, packaging, icons)' \
		'  test-mac          Run macOS tests' \
		'  test-iphone       Run iPhone 18 Pro Max iOS 27.0 tests' \
		'  test-ipad         Run iPad Air 11-inch (M4) iOS 27.0 tests' \
		'  test-iphone-ipad  Run the iPhone and iPad tests sequentially with a shared cache' \
		'  test-watch        Run the Watch tests on the reference simulator' \
		'  test-apple        Run macOS, iPhone, iPad, and Watch tests sequentially' \
		'  test              Run the Apple tests followed by the relay tests' \
		'Relay' \
		'  relay-install     Install the relay dependencies from its lockfile' \
		'  relay-test        Run relay tests' \
		'  relay-typecheck   Run relay TypeScript checks' \
		'  relay-dry-run     Validate the relay deployment without contacting Cloudflare' \
		'  relay-ci          Run all relay checks' \
		'Gate' \
		'  gate              Run the complete contribution-guide gate'

generate:
	$(RUN_WITH_TIMEOUT) Scripts/generate-project.sh

run: dev-mac

dev-mac: generate
	@$(RUN_WITH_TIMEOUT) xcodebuild -quiet build -scheme ResetRadarMac -configuration Development \
		-destination 'platform=macOS' -derivedDataPath .build/mac-run
	@open .build/mac-run/Build/Products/Development/ResetRadarMac.app

IPHONE_DESTINATION := platform=iOS Simulator,name=iPhone 18 Pro Max,OS=27.0
IPAD_DESTINATION := platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=27.0
WATCH_DESTINATION := platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)
IPA_PACKAGE := .build/ipa/ResetRadar.ipa
MAC_TEST_DERIVED_DATA := .build/derived-data/mac-tests
IOS_DERIVED_DATA := .build/derived-data/ios
WATCH_DERIVED_DATA := .build/derived-data/watch
COMMAND_TIMEOUT_SECONDS ?= 600
RUN_WITH_TIMEOUT := python3 -I Scripts/run-with-timeout.py $(COMMAND_TIMEOUT_SECONDS) --
XCODE_TEST := Scripts/run-xcode-test.sh $(COMMAND_TIMEOUT_SECONDS)

check-simulators:
	@$(RUN_WITH_TIMEOUT) Scripts/check-simulator-environment.sh

dev-iphone: check-simulators generate
	@$(RUN_WITH_TIMEOUT) xcodebuild -quiet build -scheme ResetRadar -configuration Development \
		-destination '$(IPHONE_DESTINATION)' -derivedDataPath '$(IOS_DERIVED_DATA)'

dev-ipad: check-simulators generate
	@$(RUN_WITH_TIMEOUT) xcodebuild -quiet build -scheme ResetRadar -configuration Development \
		-destination '$(IPAD_DESTINATION)' -derivedDataPath '$(IOS_DERIVED_DATA)'

dev-watch: check-simulators generate
	@$(RUN_WITH_TIMEOUT) xcodebuild -quiet build -scheme ResetRadarWatch -configuration Development \
		-destination '$(WATCH_DESTINATION)' -derivedDataPath '$(WATCH_DERIVED_DATA)'

# The package is signed with the owner's local Personal Team configuration.  It intentionally
# preserves an existing IPA so a repeat `make rel-ipa` cannot replace a package awaiting installation.
rel-ipa: generate
	@set -eu; \
	package_path='$(IPA_PACKAGE)'; \
	if [ -e "$$package_path" ]; then \
		printf '%s\n' "IPA already exists: $$package_path"; \
	else \
		workdir=$$(mktemp -d /private/tmp/reset-radar-ipa.XXXXXX); \
		trap 'rm -rf "$$workdir"' EXIT; \
		$(RUN_WITH_TIMEOUT) xcodebuild -quiet archive \
			-project ResetRadar.xcodeproj -scheme ResetRadar -configuration Release \
			-destination 'generic/platform=iOS' \
			-archivePath "$$workdir/ResetRadar.xcarchive" -allowProvisioningUpdates; \
		archive_app="$$workdir/ResetRadar.xcarchive/Products/Applications/ResetRadar.app"; \
		codesign --verify --deep --strict "$$archive_app"; \
		python3 -I Scripts/check-app-icons.py --ios-app "$$archive_app"; \
		mkdir -p "$$workdir/Payload"; \
		ditto "$$archive_app" "$$workdir/Payload/ResetRadar.app"; \
		ditto -c -k --sequesterRsrc --keepParent "$$workdir/Payload" "$$workdir/ResetRadar.ipa"; \
		mkdir "$$workdir/unpacked"; \
		ditto -x -k "$$workdir/ResetRadar.ipa" "$$workdir/unpacked"; \
		python3 -I Scripts/check-app-icons.py --ios-app "$$workdir/unpacked/Payload/ResetRadar.app"; \
		mkdir -p "$$(dirname "$$package_path")"; \
		cp "$$workdir/ResetRadar.ipa" "$$package_path"; \
		printf '%s\n' "Created IPA: $$package_path"; \
	fi

# Local Apple Development signing preserves the Release app's Keychain identity.
rel-mac-package: generate
	@COMMAND_TIMEOUT_SECONDS='$(COMMAND_TIMEOUT_SECONDS)' Scripts/package-mac-app.sh

rel-mac-install: generate
	@set -eu; \
	workdir=$$(mktemp -d /private/tmp/reset-radar-mac-fresh-install.XXXXXX); \
	trap 'rm -rf "$$workdir"' EXIT; \
	COMMAND_TIMEOUT_SECONDS='$(COMMAND_TIMEOUT_SECONDS)' Scripts/package-mac-app.sh "$$workdir/ResetRadarMac.zip"; \
	MAC_PACKAGE_PATH="$$workdir/ResetRadarMac.zip" Scripts/install-mac-app.sh

format:
	$(RUN_WITH_TIMEOUT) swift-format format --in-place --recursive $$(tr '\n' ' ' < Scripts/swift-roots.txt)

check-format:
	$(RUN_WITH_TIMEOUT) Scripts/lint-swift-format.sh

lint:
	$(RUN_WITH_TIMEOUT) swiftlint --strict

check-imports:
	$(RUN_WITH_TIMEOUT) Scripts/check-imports.sh

test-scripts:
	$(RUN_WITH_TIMEOUT) python3 -I -m unittest discover -s Scripts/tests -p 'test_*.py'

check-mac-arch: generate
	$(RUN_WITH_TIMEOUT) Scripts/check-mac-architecture.sh

test-mac: generate
	@$(XCODE_TEST) xcodebuild -quiet test -enableCodeCoverage NO \
		-scheme ResetRadarMac -destination 'platform=macOS' \
		-derivedDataPath '$(MAC_TEST_DERIVED_DATA)'

test-iphone: check-simulators generate
	@Scripts/run-ios-tests.sh $(COMMAND_TIMEOUT_SECONDS) \
		'$(IPHONE_DESTINATION)' '$(IOS_DERIVED_DATA)'

test-ipad: check-simulators generate
	@Scripts/run-ios-tests.sh $(COMMAND_TIMEOUT_SECONDS) \
		'$(IPAD_DESTINATION)' '$(IOS_DERIVED_DATA)'

# Run destinations sequentially; retain incremental builds in their shared iOS cache.
test-iphone-ipad:
	@$(MAKE) --no-print-directory test-iphone
	@$(MAKE) --no-print-directory test-ipad

test-watch: check-simulators generate
	@$(XCODE_TEST) xcodebuild -quiet test -enableCodeCoverage NO \
		-scheme ResetRadarWatch -destination '$(WATCH_DESTINATION)' \
		-derivedDataPath '$(WATCH_DERIVED_DATA)'

relay-install:
	$(RUN_WITH_TIMEOUT) npm --prefix relay ci

relay-test:
	@$(RUN_WITH_TIMEOUT) npm --prefix relay --silent test

relay-typecheck:
	$(RUN_WITH_TIMEOUT) npm --prefix relay run typecheck

relay-dry-run:
	$(RUN_WITH_TIMEOUT) npm --prefix relay run deploy:dry-run

relay-ci: relay-install relay-test relay-typecheck relay-dry-run

# Apple runs share simulator services, even though their build databases are isolated.
test-apple:
	@$(MAKE) --no-print-directory test-mac
	@$(MAKE) --no-print-directory test-iphone-ipad
	@$(MAKE) --no-print-directory test-watch

test:
	+@$(MAKE) --no-print-directory test-apple
	+@$(MAKE) --no-print-directory relay-test

gate: check-simulators generate check-format lint check-imports test-scripts check-mac-arch test-mac test-iphone-ipad test-watch relay-ci
