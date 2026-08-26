#!/bin/sh

set -eu

if [ -z "${THEOS:-}" ]; then
    echo "ERROR: THEOS is not set. Example: export THEOS=/path/to/theos" >&2
    exit 1
fi

require_file() {
    if [ ! -f "$1" ]; then
        echo "MISSING: $1" >&2
        exit 1
    fi
    echo "OK: $1"
}

require_file "$THEOS/makefiles/common.mk"
require_file "$THEOS/vendor/include/ControlCenterUIKit/CCUIToggleModule.h"
require_file "$THEOS/vendor/include/Preferences/PSListController.h"

sdk_path=""
for candidate in "$THEOS"/sdks/iPhoneOS16*.sdk; do
    if [ -d "$candidate" ]; then
        sdk_path="$candidate"
    fi
done

if [ -z "$sdk_path" ]; then
    echo "MISSING: an iPhoneOS 16.x SDK under $THEOS/sdks" >&2
    exit 1
fi

require_file "$sdk_path/System/Library/PrivateFrameworks/ControlCenterUIKit.framework/ControlCenterUIKit.tbd"
require_file "$sdk_path/System/Library/PrivateFrameworks/Preferences.framework/Preferences.tbd"
require_file "$sdk_path/usr/include/sqlite3.h"
require_file "$sdk_path/usr/lib/libsqlite3.tbd"

if ! command -v make >/dev/null 2>&1; then
    echo "MISSING: make" >&2
    exit 1
fi

if ! command -v ldid >/dev/null 2>&1; then
    echo "MISSING: ldid" >&2
    exit 1
fi

echo "OK: build environment is ready"
echo "NOTE: WorkflowKit and VoiceShortcutClient are loaded dynamically on the iPhone; build-time stubs are not required."
echo "NOTE: com.opa334.ccsupport >= 1.3.11 is a runtime dependency; verify it on the iPhone with dpkg -s com.opa334.ccsupport."
echo "NOTE: preferenceloader is a runtime dependency; verify it on the iPhone with dpkg -s preferenceloader."
