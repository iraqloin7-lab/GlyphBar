TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = GlyphBar
GlyphBar_FILES = Tweak.x
GlyphBar_CFLAGS = -fobjc-arc
GlyphBar_FRAMEWORKS = UIKit AVFoundation IOKit
include $(THEOS_MAKE_PATH)/tweak.mk
