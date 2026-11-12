APP = Logo Rave.app
SIGN_ID = -

.PHONY: build run test clean

build:
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	swiftc -O -framework AppKit -framework AVFoundation -framework QuartzCore -framework CoreAudio \
		-o "$(APP)/Contents/MacOS/Logo Rave" \
		Sources/try.m Sources/main.swift Sources/RaveWindow.swift
	cp Info.plist "$(APP)/Contents/Info.plist"
	codesign --force --sign "$(SIGN_ID)" --identifier com.zhast.bignumbers.logorave "$(APP)"

run: build
	open "$(APP)"

test:
	swiftc -O -framework AppKit -framework AVFoundation -framework QuartzCore -framework CoreAudio \
		-o /tmp/logo-rave-check \
		Sources/try.m Sources/main.swift Sources/RaveWindow.swift
	/tmp/logo-rave-check --self-test
	/tmp/logo-rave-check --theory

clean:
	rm -rf "$(APP)"
