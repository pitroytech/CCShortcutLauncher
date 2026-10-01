# Direct plist configuration

Config follows Choicy's model: a shared jailbreak-root path, direct plist read,
atomic read/modify/write, existing Darwin reload notification. No CFPreferences
or NSUserDefaults in the config path. PTPreferenceStore adds a cross-process
lock, bounded lock wait, fsync and disk readback; this is not copied Choicy code.

The canonical file is the old jailbreak plist filename with `.direct` before
`.plist`. On first access only, import old jailbreak file; use old system file
only if jailbreak file is absent. Never merge two divergent snapshots. Existing
corrupt/unreadable files block writes. Missing old values cannot be recovered.
Old files stay untouched, so an old cfprefsd domain cannot overwrite new data.
Do not install an old binary and expect it to read changes to the new file.

Native persistence tests are shared with OhMyRotate and exercise actual Objective-C
code, including multi-process updates. No remote install/respring performed.
Widget rendering / shortcut execution behavior intentionally unchanged.

## Status
CI 36814652907 passed package and native store tests. Source 3bfc7b8; no package delivered/installed. Packaging architecture verification pending.
