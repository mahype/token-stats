# Xcode statt der Command Line Tools verwenden, auch wenn xcode-select anders steht.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

BUILD_DIR := build
APP := $(BUILD_DIR)/Build/Products/Debug/Token Stats.app

.PHONY: project build test run screenshots clean

project:
	xcodegen generate --quiet

build: project
	xcodebuild -project TokenStats.xcodeproj -scheme TokenStats -configuration Debug \
		-derivedDataPath $(BUILD_DIR) -quiet build

test: project
	xcodebuild -project TokenStats.xcodeproj -scheme TokenStats -configuration Debug \
		-derivedDataPath $(BUILD_DIR) -quiet test

run: build
	-pkill -x "Token Stats"
	@while pgrep -qx "Token Stats"; do sleep 0.2; done; sleep 1
	open "$(APP)"

# Rendert die README-Bilder nach screenshots/ (Demo-Limits, echter Verbrauch).
screenshots: build
	-pkill -x "Token Stats"
	@while pgrep -qx "Token Stats"; do sleep 0.2; done
	TOKENSTATS_SCREENSHOTS="$(CURDIR)/screenshots" "$(APP)/Contents/MacOS/Token Stats"

clean:
	rm -rf $(BUILD_DIR) TokenStats.xcodeproj
