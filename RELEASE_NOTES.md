# CCShortcutLauncher 1.5.1

This release expands CCShortcutLauncher from one launcher into a configurable
set of Control Center modules while keeping Shortcut execution in the
background.

## What's new since 1.3.0

- Create between one and eight independent Control Center modules.
- A module with one Shortcut runs it immediately; a module with multiple
  Shortcuts opens an ordered picker.
- Add, remove, rename, and reorder modules and their Shortcuts from Settings.
- The resolver automatically follows additions, deletions, renames, and icon
  changes in My Shortcuts, with a manual refresh button when needed.
- Single-Shortcut modules use the Shortcut icon. Multi-Shortcut modules can
  choose from 44 monochrome icons, synchronized across tweak Settings,
  Settings → Control Center, and Control Center.
- Vietnamese and English interfaces are included; Vietnamese is the default.
- Improved retry behavior after boot, duplicate-run protection, icon fallbacks,
  and user-facing guidance.

## Compatibility

- Rootless jailbreaks on iOS 16.0 through iOS 17.3.1.
- CCSupport 1.3.11 or newer.
- PreferenceLoader.

The 1.5.1 release candidate was validated with automatic catalog updates,
Shortcut deletion, repeated taps, and completed background executions without
errors, retries, crashes, or Safe Mode.

Add the repository to Sileo: https://dinhno12313.github.io/
