ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = cslresolved

cslresolved_FILES = main.m
cslresolved_CFLAGS = -fobjc-arc -fmodules-cache-path=$(CURDIR)/../.theos/module-cache
cslresolved_CODESIGN_FLAGS = -Sentitlements.plist
cslresolved_FRAMEWORKS = Foundation CoreFoundation
cslresolved_LIBRARIES = sqlite3
cslresolved_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk
