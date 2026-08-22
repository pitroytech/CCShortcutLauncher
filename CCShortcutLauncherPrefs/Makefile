THEOS_PACKAGE_SCHEME = rootless

ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CCShortcutLauncherPrefs

CCShortcutLauncherPrefs_FILES = CSLRootListController.m CSLShortcutOrderController.m ../CSLShortcutIcon.m
CCShortcutLauncherPrefs_CFLAGS = -fobjc-arc -fmodules-cache-path=$(CURDIR)/../.theos/module-cache
CCShortcutLauncherPrefs_FRAMEWORKS = Foundation CoreFoundation UIKit CoreText
CCShortcutLauncherPrefs_PRIVATE_FRAMEWORKS = Preferences
CCShortcutLauncherPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
