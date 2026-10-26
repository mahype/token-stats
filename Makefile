# Xcode statt der Command Line Tools verwenden, auch wenn xcode-select anders steht.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

BUILD_DIR := build
APP := $(BUILD_DIR)/Build/Products/Debug/Token Stats.app
RELEASE_APP := $(BUILD_DIR)/Build/Products/Release/Token Stats.app
VERSION := $(shell sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
DMG := $(BUILD_DIR)/Token-Stats-$(VERSION).dmg

.PHONY: project build test run screenshots release publish clean ios ios-run

# iCloud-Übertragung an die iOS-App (Issue #11) nur auf Wunsch: `make build ICLOUD=1` nimmt die
# Entitlements mit iCloud-Container. Das verlangt ein Provisioning-Profil (für Developer ID eines
# mit iCloud-Capability, PROVISIONING_PROFILE_SPECIFIER setzen); ohne Profil bricht Xcode ab.
ICLOUD ?=
ICLOUD_SIGNING := $(if $(ICLOUD),CODE_SIGN_ENTITLEMENTS=Config/TokenStats-iCloud.entitlements,)

project:
	xcodegen generate --quiet

# Debug-Builds signieren mit einem „Apple Development“-Zertifikat aus dem Schlüsselbund, falls
# eines da ist, sonst ad hoc. Die Widgets brauchen die Team-Signatur: Die App Group heißt
# <Team-ID>.de.mahype.TokenStats (project.yml), und macOS lässt nur Apps desselben Teams an den
# Container. Ad hoc signiert läuft die App, aber die Widgets bleiben bei „Token Stats öffnen“.
DEV_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)
DEV_TEAM ?= $(shell [ -n "$(DEV_IDENTITY)" ] && security find-certificate -c "$(DEV_IDENTITY)" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p')
DEBUG_SIGNING := $(if $(DEV_TEAM),CODE_SIGN_IDENTITY="$(DEV_IDENTITY)" DEVELOPMENT_TEAM=$(DEV_TEAM),)

build: project
	xcodebuild -project TokenStats.xcodeproj -scheme TokenStats -configuration Debug \
		-derivedDataPath $(BUILD_DIR) -quiet build $(DEBUG_SIGNING) $(ICLOUD_SIGNING)

test: project
	xcodebuild -project TokenStats.xcodeproj -scheme TokenStats -configuration Debug \
		-derivedDataPath $(BUILD_DIR) -quiet test $(DEBUG_SIGNING)

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
		OTHER_CODE_SIGN_FLAGS=--timestamp CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO $(ICLOUD_SIGNING)
	Scripts/sign-sparkle.sh "$(RELEASE_APP)" "$(SIGN_IDENTITY)"
	codesign --verify --strict --deep "$(RELEASE_APP)"
	Scripts/make-dmg.sh "$(RELEASE_APP)" "$(DMG)"
	codesign --sign "$(SIGN_IDENTITY)" --timestamp "$(DMG)"
	xcrun notarytool submit "$(DMG)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(DMG)"
	spctl --assess --type open --context context:primary-signature -vv "$(DMG)"
	shasum -a 256 "$(DMG)"

# Tag, GitHub-Release und Sparkle-Appcast für das DMG aus `make release`.
publish:
	Scripts/publish.sh

# iOS-App (Issue #11) im Simulator: bauen, installieren, mit Demo-Werten starten.
# Auf ein Gerät kommt sie nur mit Team-Signatur und Profil (Xcode, Signing & Capabilities).
SIMULATOR ?= iPhone 18 Pro
IOS_APP := $(BUILD_DIR)/Build/Products/Debug-iphonesimulator/Token Stats.app

ios: project
	xcodebuild -project TokenStats.xcodeproj -scheme TokenStatsiOS -configuration Debug \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' -derivedDataPath $(BUILD_DIR) -quiet build

ios-run: ios
	xcrun simctl boot "$(SIMULATOR)" 2>/dev/null || true
	-open -b com.apple.iphonesimulator
	xcrun simctl install booted "$(IOS_APP)"
	SIMCTL_CHILD_TOKENSTATS_DEMO=1 xcrun simctl launch --terminate-running-process booted de.mahype.TokenStats >/dev/null

clean:
	rm -rf $(BUILD_DIR) TokenStats.xcodeproj
