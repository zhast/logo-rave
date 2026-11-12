APP = Logo Rave.app
SIGN_ID = -

.PHONY: build run test clean

build:
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	swiftc -O -framework AppKit -framework AVFoundation -framework QuartzCore -framework CoreAudio \
		-o "$(APP)/Contents/MacOS/Logo Rave" \
		Sources/try.m Sources/main.swift Sources/RaveWindow.swift Sources/RaveController.swift Sources/SymbolStyle.swift
	cp Info.plist "$(APP)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(APP)/Contents/Resources/"
	codesign --force --sign "$(SIGN_ID)" --identifier com.zhast.bignumbers.logorave "$(APP)"

run: build
	open "$(APP)"

test:
	swiftc -O -framework AppKit -framework AVFoundation -framework QuartzCore -framework CoreAudio \
		-o /tmp/logo-rave-check \
		Sources/try.m Sources/main.swift Sources/RaveWindow.swift Sources/RaveController.swift Sources/SymbolStyle.swift
	/tmp/logo-rave-check --self-test
	/tmp/logo-rave-check --theory

clean:
	rm -rf "$(APP)"

.PHONY: icon
icon:
	mkdir -p build/AppIcon.iconset Resources
	swiftc Sources/SymbolStyle.swift Sources/make-icon.swift -o build/make-icon
	build/make-icon build/AppIcon.png
	@for size in 16 32 128 256 512; do \
		sips -z $$size $$size build/AppIcon.png --out build/AppIcon.iconset/icon_$${size}x$${size}.png >/dev/null; \
		double=$$((size * 2)); \
		sips -z $$double $$double build/AppIcon.png --out build/AppIcon.iconset/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
