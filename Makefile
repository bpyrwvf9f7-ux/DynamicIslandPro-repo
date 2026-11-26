export THEOS_PACKAGE_SCHEME = rootless
THEOS_PLATFORM_DEB_COMPRESSION_TYPE := gzip
TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DynamicIslandPro
DynamicIslandPro_FILES = Tweak.xm
DynamicIslandPro_FRAMEWORKS = UIKit Foundation QuartzCore
DynamicIslandPro_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
