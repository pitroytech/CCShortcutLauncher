#ifndef CSLDiagnostics_h
#define CSLDiagnostics_h

/// Normal releases keep icon routing quiet. Add
/// `-DCSL_ICON_DIAGNOSTICS=1` to the relevant target CFLAGS when collecting an
/// icon probe; failures remain logged regardless of this switch.
#ifndef CSL_ICON_DIAGNOSTICS
#define CSL_ICON_DIAGNOSTICS 0
#endif

#if CSL_ICON_DIAGNOSTICS
#define CSLIconDiagnosticLog(...) NSLog(__VA_ARGS__)
#else
#define CSLIconDiagnosticLog(...) do { } while (0)
#endif

#endif
