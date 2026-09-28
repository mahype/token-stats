# Xcode statt der Command Line Tools verwenden, auch wenn xcode-select anders steht.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

BUILD_DIR := build
APP := $(BUILD_DIR)/Build/Products/Debug/Token Stats.app

.PHONY: project build test run clean

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
	@while pgrep -qx "Token Stats"; do sleep 0.2; done
	open "$(APP)"

clean:
	rm -rf $(BUILD_DIR) TokenStats.xcodeproj
