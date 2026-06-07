.PHONY: run build clean app dmg xcode

BUILD_SCRIPT := scripts/build.sh

run:
	cd .. && swift run --package-path native

build:
	swift build -c release

clean:
	rm -rf .build *.app *.dmg

app:
	bash $(BUILD_SCRIPT)

dmg:
	bash $(BUILD_SCRIPT) dmg

xcode:
	@echo "To open in Xcode:"
	@echo "  1. Launch Xcode"
	@echo "  2. File -> Open -> select the 'native' folder"
	@echo "  3. Xcode will resolve the SwiftPM package automatically"
	@echo ""
	@echo "Or from CLI:  open -a Xcode native"
