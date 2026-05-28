# qudong - CIODIY driver bootstrap repository

GitHub: https://github.com/TheOneAdonis/qudong

This fork is being reshaped from a raw driver mirror into a lightweight Windows driver bootstrap system.

The intended use case is simple: after a fresh Windows 10/11 install, restore enough core drivers to get the machine usable and online. After that, Windows Update, OEM support tools, or vendor installers can finish non-critical or large driver updates.

## Project scope

Qudong should focus on:

- network, WiFi, Bluetooth, chipset, MEI, RST, Serial IO, audio, and similar bootstrap drivers;
- verified packages with URL + SHA256;
- conservative installation through Windows driver store tooling;
- dry-run matching before installation;
- clear separation between installable packages and advisory-only packages.

Qudong should not try to mirror every large GPU package, OEM utility, printer suite, or vendor control panel package.

## Structure

```text
qudong/
  manifest.json                      # runtime manifest consumed by installers
  driver_packages.json               # current raw/source manifest
  schema/driver-package.schema.json  # manifest schema
  tools/Test-QudongManifest.ps1      # validation and quality checks
  tools/Build-QudongManifest.ps1     # deterministic manifest generator
  installer/Qudong.Bootstrap.ps1     # safe dry-run/install entry point
  docs/design.md                     # redesign notes and migration plan
  packages/                          # ZIP files for GitHub Release assets
  Drivers/                           # optional expanded INF folders
```

## Validate manifests

Run these commands from the repository root in PowerShell 7+:

```powershell
./tools/Test-QudongManifest.ps1 -ManifestPath manifest.json
./tools/Test-QudongManifest.ps1 -ManifestPath driver_packages.json
```

Use strict mode when warnings should fail the build:

```powershell
./tools/Test-QudongManifest.ps1 -ManifestPath manifest.json -Strict
```

The validator checks for common problems such as missing required fields, invalid SHA256 values, duplicate package IDs, missing dependencies, advisory/installable confusion, suspicious device class mismatches, and mojibake in titles.

## Generate a manifest

`driver_packages.json` can be used as the source for a generated manifest:

```powershell
./tools/Build-QudongManifest.ps1 `
  -SourcePath driver_packages.json `
  -OutputPath manifest.generated.json `
  -Repository "https://github.com/TheOneAdonis/qudong" `
  -Release "v1.1.0"
```

The long-term goal is to stop hand-editing `manifest.json` and generate it from a source-of-truth file.

## Dry-run driver matching

The bootstrap installer is conservative by default. Without `-Apply`, it only enumerates present devices and shows matching packages.

```powershell
./installer/Qudong.Bootstrap.ps1 -ManifestPath manifest.json
```

To include medium-risk packages in the dry run:

```powershell
./installer/Qudong.Bootstrap.ps1 -ManifestPath manifest.json -AllowMediumRisk
```

To install matched packages from a local cache, run as Administrator and pass `-Apply`:

```powershell
./installer/Qudong.Bootstrap.ps1 -ManifestPath manifest.json -PackageCache .qudong-cache -Apply
```

To allow downloads before verification:

```powershell
./installer/Qudong.Bootstrap.ps1 -ManifestPath manifest.json -PackageCache .qudong-cache -OnlineDownload -Apply
```

The installer verifies SHA256 before extraction and uses `pnputil /add-driver ... /subdirs /install` for INF-style packages.

## Publish release assets

Current manual flow:

1. Prepare driver ZIP packages.
2. Upload ZIP files to the GitHub Release referenced by the manifest.
3. Fill each package URL and SHA256.
4. Run manifest validation.
5. Dry-run matching on test machines before publishing as stable.

## Local offline use

Copy the repository, release ZIP packages, and/or expanded driver folders to a USB drive. Run the bootstrap installer in dry-run mode first, then install only after reviewing the matched packages.

See `docs/design.md` for the redesign rationale and migration plan.
