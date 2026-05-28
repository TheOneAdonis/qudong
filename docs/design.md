# Qudong redesign notes

This document narrows the project goal and defines the target architecture for the fork.

## Product goal

Qudong should be a lightweight Windows driver bootstrap system, not a full replacement for Windows Update, OEM tools, or large driver suites.

Primary use case:

1. A Windows 10/11 machine has just been reinstalled.
2. Network, storage, chipset, audio, or platform devices may be missing drivers.
3. Qudong provides a trusted offline/near-offline base driver library.
4. After network access is restored, Windows Update or the OEM/vendor source can finish non-critical updates.

## Non-goals

- Mirror every GPU, printer, OEM utility, and vendor control panel package.
- Force-install drivers that Windows ranks lower than the current driver.
- Replace Windows Update driver selection.
- Distribute drivers whose redistribution rights are unknown.

## Architecture

```text
packages.source.json / driver_packages.json
        |
        v
tools/Build-QudongManifest.ps1
        |
        v
manifest.json or manifest.generated.json
        |
        v
installer/Qudong.Bootstrap.ps1
        |
        v
pnputil / DISM / Windows driver store
```

## Recommended repository layout

```text
manifest.json                      # runtime manifest consumed by the installer
packages.source.json               # future source-of-truth package metadata
schema/driver-package.schema.json  # machine-readable schema
tools/Test-QudongManifest.ps1      # validation and quality gates
tools/Build-QudongManifest.ps1     # deterministic manifest generation
installer/Qudong.Bootstrap.ps1     # safe bootstrap installer entry point
docs/design.md                     # architecture and migration plan
```

## Package modes

Every package should eventually declare one explicit mode.

```json
{
  "mode": "offline_bootstrap"
}
```

Recommended values:

- `offline_bootstrap`: small and important packages used to restore basic functionality.
- `installable`: ordinary packages that can be downloaded, verified, and installed automatically.
- `advisory_only`: packages that should be shown as guidance but not auto-installed.

GPU packages, large vendor installers, OEM-specific utilities, and packages without a verified URL/SHA256 should usually be `advisory_only`.

## Safety model

The installer should be conservative by default.

1. Enumerate devices.
2. Match by exact hardware ID or compatible ID.
3. Filter by OS, architecture, dependency, conflict, and risk.
4. Verify package hash before extraction.
5. Add drivers to the driver store using `pnputil`.
6. Let Windows Plug and Play ranking choose the driver.
7. Verify device state after installation.
8. Never force-install by default.

## Migration plan

### Phase 1: validation

- Keep the existing manifests.
- Add schema and validation scripts.
- Detect missing URLs, missing hashes, mojibake, dependency gaps, and suspicious category/deviceClass mismatches.

### Phase 2: source-of-truth split

- Treat `packages.source.json` or `driver_packages.json` as the editable source.
- Generate `manifest.json` from the source with stable ordering.
- Stop editing `manifest.json` by hand.

### Phase 3: bootstrap installer

- Support dry-run matching first.
- Support local ZIP packages and verified downloads.
- Install only INF-style drivers through `pnputil` initially.
- Add DISM support later for offline Windows images.

### Phase 4: online handoff

- Restore network and core devices first.
- For large or sensitive drivers, point users to Windows Update, OEM support pages, or vendor installers.
