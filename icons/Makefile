# Make Android icon resources using ImageMagick

SOURCE_ICON := icon2.png
CONVERT_OPTIONS := -filter Lanczos

ALL_OUTPUT := \
  ../android/res/drawable-ldpi/ic_launcher.png \
  ../android/res/drawable-mdpi/ic_launcher.png \
  ../android/res/drawable-hdpi/ic_launcher.png \
  ../android/res/drawable-xhdpi/ic_launcher.png

.PHONY: default
default: $(ALL_OUTPUT)

.PHONY: clean
clean:
	rm -f $(ALL_OUTPUT)

../android/res/drawable-ldpi/ic_launcher.png: $(SOURCE_ICON)
	convert $< $(CONVERT_OPTIONS) -geometry 36x36 $@

../android/res/drawable-mdpi/ic_launcher.png: $(SOURCE_ICON)
	convert $< $(CONVERT_OPTIONS) -geometry 48x48 $@

../android/res/drawable-hdpi/ic_launcher.png: $(SOURCE_ICON)
	convert $< $(CONVERT_OPTIONS) -geometry 72x72 $@

../android/res/drawable-xhdpi/ic_launcher.png: $(SOURCE_ICON)
	convert $< $(CONVERT_OPTIONS) -geometry 96x96 $@
