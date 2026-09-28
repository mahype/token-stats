# Xcode statt der Command Line Tools verwenden, auch wenn xcode-select anders steht.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

BUILD_DIR := build
APP := $(BUILD_DIR)/Build/Products/Debug/Token Stats.app
RELEASE_APP := $(BUILD_DIR)/Build/Products/Release/Token Stats.app
VERSION := $(shell sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
DMG := $(BUILD_DIR)/Token-Stats-$(VERSION).dmg

.PHONY: project build test run screenshots release clean

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

# Rendert die README-Bilder nach screenshots/ (nur Demo-Werte).
screenshots: build
	-pkill -x "Token Stats"
	@while pgrep -qx "Token Stats"; do sleep 0.2; done
	TOKENSTATS_SCREENSHOTS="$(CURDIR)/screenshots" "$(APP)/Contents/MacOS/Token Stats"

# Release-Build (Universal: Apple Silicon und Intel) als DMG: mit Developer ID signiert,
# von Apple notarisiert und gestapelt. Braucht das Zertifikat „Developer ID Application“
# im Schlüsselbund und das notarytool-Profil (siehe CLAUDE.md).
TEAM_ID := 2GA7DQ3P3Z
SIGN_IDENTITY ?= Developer ID Application
NOTARY_PROFILE ?= notary

release: project
	xcodebuild -project TokenStats.xcodeproj -scheme TokenStats -configuration Release \
		-derivedDataPath $(BUILD_DIR) -quiet build \
		CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" DEVELOPMENT_TEAM=$(TEAM_ID) \
		OTHER_CODE_SIGN_FLAGS=--timestamp CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
	codesign --verify --strict --deep "$(RELEASE_APP)"
	Scripts/make-dmg.sh "$(RELEASE_APP)" "$(DMG)"
	codesign --sign "$(SIGN_IDENTITY)" --timestamp "$(DMG)"
	xcrun notarytool submit "$(DMG)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(DMG)"
	spctl --assess --type open --context context:primary-signature -vv "$(DMG)"
	shasum -a 256 "$(DMG)"

clean:
	rm -rf $(BUILD_DIR) TokenStats.xcodeproj
