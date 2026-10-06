APP=WheelFlip
BUILD=build

.PHONY: gen build test install reset-permission

gen:
	xcodegen generate

build: gen
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
