ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VCam

VCam_FILES = Tweak.xm MediaManager.m
VCam_CFLAGS = -fobjc-arc
VCam_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo CoreImage Photos PhotosUI
VCam_PRIVATE_FRAMEWORKS = 

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += vcamsettings
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard"
