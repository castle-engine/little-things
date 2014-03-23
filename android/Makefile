# To release run like
#   make BUILD=release
# to build in release mode. Make sure ant.properties contains
#   key.store=.../michalis.keystore
#   key.alias=michalis
# See http://developer.android.com/tools/publishing/app-signing.html
#
# Normal
#   make
# builds a release version of the app, but signed with debug key.
# Use
#   make debug
# to have a debug version of the app with debug information, usable
# with ndk-gdb, see
# https://sourceforge.net/p/castle-engine/wiki/Android%20development/#debugging-running-application-on-an-android-device-using-ndk-gdb

BUILD=debug

.PHONY: default
default: data
	cd ../../castle_game_engine/ && ppcrossarm -Tandroid -CfVFPV3 -dRELEASE $${CASTLE_FPC_OPTIONS:-} @castle-fpc.cfg ../little_things/code/little_things_android.lpr
	mkdir -p libs/armeabi/
	cp -f ../code/liblittle_things_android.so libs/armeabi/liblittle_things_android.so
	$(MAKE) build-finish

.PHONY: debug
debug: data
	cd ../../castle_game_engine/ && ppcrossarm -Tandroid -CfVFPV3 -dDEBUG $${CASTLE_FPC_OPTIONS:-} @castle-fpc.cfg ../little_things/code/little_things_android.lpr
	cp -f ../code/liblittle_things_android.so jni/liblittle_things_android.so
	export NDK_DEBUG=1 && ndk-build
	$(MAKE) build-finish

.PHONY: build-finish
build-finish:
	ant $(BUILD)
#	adb uninstall net.sourceforge.castleengine.littlethings
	adb install -r bin/LittleThings-$(BUILD).apk
	adb shell am start -a android.intent.action.MAIN -n net.sourceforge.castleengine.littlethings/android.app.NativeActivity

.PHONY: clean
clean:
	rm -Rf bin/ gen/ libs/ obj/ assets/ jni/liblittle_things_android.so

# You only need to call it once
.PHONY: init
init:
	android update lib-project -p . --target 1

.PHONY: data
data:
	rm -Rf assets/
	cp -R ../data/ assets/
	find assets/ -type f \
	   '(' -iname '*~' -or \
	       -iname '*.xcf' -or \
	       -iname '*.blend' -or \
	       -iname '*.blend1' -or \
	       -iname '*.blend2' ')' \
	   -exec rm -f '{}' ';'
