PROJECT     := WTH.xcodeproj
SCHEME      := WTH
DESTINATION := platform=macOS
XCODEBUILD  := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)'

.PHONY: build release test clean

build:
	$(XCODEBUILD) -configuration Debug build

release:
	$(XCODEBUILD) -configuration Release build

test:
	$(XCODEBUILD) -configuration Debug test

clean:
	$(XCODEBUILD) clean
	rm -rf build DerivedData
