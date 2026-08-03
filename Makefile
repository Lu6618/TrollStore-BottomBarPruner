TARGET := iphone:clang:latest:15.0
ARCHS = arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BottomBarPruner
BottomBarPruner_FILES = BottomBarPruner.mm
BottomBarPruner_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new
BottomBarPruner_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
