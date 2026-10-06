APP=WheelFlip
BUILD=build

.PHONY: gen build test install reset-permission

gen:
	xcodegen generate

# The Release binary is stripped in place (see project.yml), so the product is removed first to
# force a relink. Otherwise a rebuild that only re-signs the app, such as a version bump, would
# regenerate the dSYM from the already stripped binary and leave it empty.
build: gen
	rm -rf $(BUILD)/Build/Products/Release/$(APP).app $(BUILD)/Build/Products/Release/$(APP).app.dSYM
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Release \
	  -derivedDataPath $(BUILD) -destination 'platform=macOS,arch=arm64' build

test: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -derivedDataPath $(BUILD) \
	  -destination 'platform=macOS,arch=arm64' test

install: build
	rm -rf /Applications/$(APP).app
	cp -R $(BUILD)/Build/Products/Release/$(APP).app /Applications/
	@du -sh /Applications/$(APP).app

reset-permission:
	tccutil reset Accessibility uz.stiv.wheelflip
