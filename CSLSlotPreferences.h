#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One Control Center module is one slot. Every slot owns its own ordered list
/// of Shortcuts, so a user can keep work Shortcuts in one module and home
/// Shortcuts in another.
FOUNDATION_EXPORT NSUInteger const CSLMinimumModuleSlotCount;
FOUNDATION_EXPORT NSUInteger const CSLMaximumModuleSlotCount;
FOUNDATION_EXPORT NSUInteger const CSLDefaultModuleSlotCount;

/// Number of modules the provider vends, clamped to the range above.
NSUInteger CSLModuleSlotCount(void);
void CSLSetModuleSlotCount(NSUInteger count);

/// Control Center module identifier for a slot. Slot 0 keeps the pre-1.4
/// identifier so an existing Control Center layout survives the update.
NSString *CSLModuleIdentifierForSlot(NSUInteger slot);

/// Slot index for a module identifier, or NSNotFound when the identifier does
/// not belong to this tweak.
NSUInteger CSLSlotForModuleIdentifier(NSString *_Nullable identifier);

/// User supplied module name, or nil when the slot uses its default name.
NSString *_Nullable CSLSlotName(NSUInteger slot);
void CSLSetSlotName(NSString *_Nullable name, NSUInteger slot);

/// Name shown in Settings and in the Control Center popup.
NSString *CSLDisplayNameForSlot(NSUInteger slot);

/// Validated catalog written by the resolver daemon, sorted by name.
NSArray<NSDictionary<NSString *, id> *> *CSLShortcutCatalog(void);

/// Workflow identifiers assigned to a slot, in user order. Empty by default:
/// loading the catalog never assigns Shortcuts to a module on its own.
NSArray<NSString *> *CSLShortcutIDsForSlot(NSUInteger slot);
void CSLSetShortcutIDs(NSArray<NSString *> *identifiers, NSUInteger slot);

/// Catalog entries assigned to a slot, in user order, skipping identifiers that
/// are no longer in the catalog.
NSArray<NSDictionary<NSString *, id> *> *CSLEntriesForSlot(NSUInteger slot);

/// Moves a pre-1.4 single-module selection into slot 0. Safe to call more than
/// once; call it from Settings only, never from SpringBoard.
void CSLMigrateLegacySelectionIfNeeded(void);

NS_ASSUME_NONNULL_END
