# ─── Oat build + distribution pipeline ──────────────────────────────
#
# Usage:
#   make app       – build release binary and assemble the .app bundle
#   make sign      – codesign the bundle (requires SIGN_ID env var)
#   make notarize  – upload to Apple notarization service
#   make dmg       – create distributable DMG (requires create-dmg: brew install create-dmg)
#   make clean     – remove build artifacts
#
# Required env vars for signing:
#   SIGN_ID        – e.g. "Developer ID Application: Your Name (TEAM_ID)"
#   APPLE_ID       – Apple ID email for notarization
#   APPLE_TEAM     – 10-character Team ID
#   APPLE_PASS     – App-specific password (from appleid.apple.com)
# ─────────────────────────────────────────────────────────────────────────────

APP_NAME    = Oat
BUNDLE_ID   = com.oat.app
VERSION     = $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

BUILD_DIR   = .build
RELEASE_DIR = $(BUILD_DIR)/release
BUNDLE      = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS    = $(BUNDLE)/Contents
MACOS_DIR   = $(CONTENTS)/MacOS
RES_DIR     = $(CONTENTS)/Resources
FWKS_DIR    = $(CONTENTS)/Frameworks
DMG_DIR     = $(BUILD_DIR)/dmg

ENTITLEMENTS = Oat.entitlements

# ─── Targets ──────────────────────────────────────────────────────────────────

.PHONY: app sign notarize dmg clean

## 1. Build release binary + assemble .app bundle
app:
	swift build -c release
	@echo "▸ Assembling $(BUNDLE)"
	@rm -rf $(BUNDLE)
	@mkdir -p $(MACOS_DIR) $(RES_DIR) $(FWKS_DIR)

	# Binary
	cp $(RELEASE_DIR)/$(APP_NAME) $(MACOS_DIR)/

	# Info.plist (goes directly under Contents/, not Resources/)
	cp Resources/Info.plist $(CONTENTS)/

	# App icon (copy if it exists)
	@if [ -f Resources/AppIcon.icns ]; then \
	    cp Resources/AppIcon.icns $(RES_DIR)/; \
	fi

	# Sparkle.framework — copy from SPM build output
	@SPARKLE_FWK=$$(find $(RELEASE_DIR) -name "Sparkle.framework" -type d 2>/dev/null | head -1); \
	if [ -n "$$SPARKLE_FWK" ]; then \
	    echo "▸ Embedding $$SPARKLE_FWK"; \
	    cp -R "$$SPARKLE_FWK" $(FWKS_DIR)/; \
	else \
	    echo "⚠ Sparkle.framework not found in build output — skipping"; \
	fi

	@echo "✓ Bundle assembled at $(BUNDLE)"

## 2. Code-sign the bundle (hardened runtime for notarization)
sign: app
ifndef SIGN_ID
	$(error SIGN_ID is not set. Export it: export SIGN_ID="Developer ID Application: Your Name (TEAM_ID)")
endif
	@echo "▸ Signing Frameworks"
	@find $(FWKS_DIR) -name "*.framework" -type d | while read fwk; do \
	    codesign --force --sign "$(SIGN_ID)" \
	        --options runtime \
	        --entitlements $(ENTITLEMENTS) \
	        "$$fwk"; \
	done

	@echo "▸ Signing binary"
	codesign --force --sign "$(SIGN_ID)" \
	    --options runtime \
	    --entitlements $(ENTITLEMENTS) \
	    $(MACOS_DIR)/$(APP_NAME)

	@echo "▸ Signing bundle"
	codesign --force --deep --sign "$(SIGN_ID)" \
	    --options runtime \
	    --entitlements $(ENTITLEMENTS) \
	    $(BUNDLE)

	@echo "▸ Verifying"
	codesign --verify --deep --strict $(BUNDLE)
	spctl --assess --type execute --verbose $(BUNDLE) || true
	@echo "✓ Signed"

## 3. Notarize with Apple
notarize: sign
ifndef APPLE_ID
	$(error APPLE_ID is not set)
endif
ifndef APPLE_TEAM
	$(error APPLE_TEAM is not set)
endif
ifndef APPLE_PASS
	$(error APPLE_PASS is not set)
endif
	@echo "▸ Zipping for notarization"
	ditto -c -k --keepParent $(BUNDLE) $(BUILD_DIR)/$(APP_NAME).zip

	@echo "▸ Submitting to notarization service"
	xcrun notarytool submit $(BUILD_DIR)/$(APP_NAME).zip \
	    --apple-id "$(APPLE_ID)" \
	    --team-id "$(APPLE_TEAM)" \
	    --password "$(APPLE_PASS)" \
	    --wait

	@echo "▸ Stapling ticket"
	xcrun stapler staple $(BUNDLE)
	@echo "✓ Notarized and stapled"

## 4. Create DMG
dmg: notarize
	@echo "▸ Creating DMG"
	@mkdir -p $(DMG_DIR)
	@rm -f $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg
	create-dmg \
	    --volname "$(APP_NAME) $(VERSION)" \
	    --window-pos 200 120 \
	    --window-size 600 400 \
	    --icon-size 100 \
	    --icon "$(APP_NAME).app" 150 185 \
	    --hide-extension "$(APP_NAME).app" \
	    --app-drop-link 450 185 \
	    $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg \
	    $(BUNDLE)
	@echo "✓ DMG: $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg"

## 5. Clean
clean:
	rm -rf $(BUILD_DIR)/$(APP_NAME).app \
	       $(BUILD_DIR)/$(APP_NAME).zip \
	       $(BUILD_DIR)/$(APP_NAME)-*.dmg \
	       $(DMG_DIR)
	@echo "✓ Cleaned"
