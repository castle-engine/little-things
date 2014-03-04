# Extension of executable is determined by target operating system,
# that in turn depends on 1. -T options in CASTLE_FPC_OPTIONS and
# 2. current OS, if no -T inside CASTLE_FPC_OPTIONS. It's easiest to just
# use "fpc -iTO", to avoid having to detect OS (or parse CASTLE_FPC_OPTIONS)
# in the Makefile.
TARGET_OS = $(shell fpc -iTO $${CASTLE_FPC_OPTIONS:-})
EXE_EXTENSION = $(shell if '[' '(' $(TARGET_OS) '=' 'win32' ')' -o '(' $(TARGET_OS) '=' 'win64' ')' ']'; then echo '.exe'; else echo ''; fi)

.PHONY: standalone
standalone:
	cd ../castle_game_engine/ && \
	  fpc -dRELEASE -dCASTLE_WINDOW_BEST_NOGUI @castle-fpc.cfg \
	  $${CASTLE_FPC_OPTIONS:-} \
	  ../little_things/code/little_things.lpr
	mv code/little_things$(EXE_EXTENSION) .

.PHONY: clean
clean:
	rm -f \
	       little_things      little_things.exe \
	  code/little_things code/little_things.exe \
	  code/liblittle_things.so
	find data/ -iname '*~' -exec rm -f '{}' ';'
	$(MAKE) -C ../castle_game_engine/ clean

FILES := --exclude *.xcf --exclude '*.blend*' README.txt data/
WINDOWS_FILES := $(FILES) little_things.exe ../www/pack/win32_dlls/*.dll
UNIX_FILES    := $(FILES) little_things

.PHONY: release-win32
release-win32: clean standalone
	rm -Rf little_things-win32.zip
	zip -r little_things-win32.zip $(WINDOWS_FILES)

.PHONY: release-linux
release-linux: clean standalone
	rm -Rf little_things-linux-i386.tar.gz
	tar czvf little_things-linux-i386.tar.gz $(UNIX_FILES)
