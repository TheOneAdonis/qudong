[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ManifestPath = "manifest.json",
    [string]$PackageCache = ".qudong-cache",
    [switch]$Apply,
    [switch]$AllowMediumRisk,
    [switch]$AllowHighRisk,
    [switch]$IncludeAdvisory,
    [switch]$OnlineDownload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "== $Text =="
}

function Normalize-Array {
    param($Value)
    if ($null -eq $Value) {
        return @()
    }
    if ($Value -is [System.Array]) {
        return @($Value)
    }
    return @($Value)
}

function Get-DeviceHardwareIds {
    $devices = @()
    try {
        $pnpDevices = Get-PnpDevice -PresentOnly -ErrorAction Stop
    } catch {
        Write-Warning "Get-PnpDevice is unavailable or failed. Run in an elevated Windows PowerShell session. $($_.Exception.Message)"
        return @()
    }

    foreach ($device in $pnpDevices) {
        $ids = @()
        try {
            $properties = Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName "DEVPKEY_Device_HardwareIds", "DEVPKEY_Device_CompatibleIds" -ErrorAction SilentlyContinue
            foreach ($property in $properties) {
                $ids += Normalize-Array $property.Data
            }
        } catch {
            # Some devices do not expose both properties. Skip quietly.
        }

        $devices += [pscustomobject]@{
            InstanceId = $device.InstanceId
            Class = $device.Class
            FriendlyName = $device.FriendlyName
            Status = $device.Status
            HardwareIds = @($ids | Where-Object { $_ } | Select-Object -Unique)
        }
    }

    return $devices
}

function Test-PackageAllowed {
    param($Package)

    if ($Package.mode -eq "advisory_only" -and -not $IncludeAdvisory) {
        return $false
    }
    if ($Package.risk -eq "high" -and -not $AllowHighRisk) {
        return $false
    }
    if ($Package.risk -eq "medium" -and -not ($AllowMediumRisk -or $AllowHighRisk)) {
        return $false
    }
    return $true
}

function Get-PackageMatches {
    param($Manifest, $Devices)

    $matches = @()
    foreach ($packageKey in $Manifest.packages.PSObject.Properties.Name) {
        $pkg = $Manifest.packages.$packageKey
        if (-not (Test-PackageAllowed $pkg)) {
            continue
        }

        $packageHwids = Normalize-Array $pkg.hwids
        foreach ($device in $Devices) {
            $matchedIds = @($device.HardwareIds | Where-Object { $packageHwids -contains $_ })
            if ($matchedIds.Count -gt 0) {
                $matches += [pscustomobject]@{
                    PackageKey = $packageKey
                    Id = $pkg.id
                    Title = $pkg.title
                    Vendor = $pkg.vendor
                    Category = $pkg.category
                    Risk = $pkg.risk
                    InstallOrder = if ($pkg.installOrder) { [int]$pkg.installOrder } else { 999 }
                    Url = $pkg.url
                    Sha256 = $pkg.sha256
                    Mode = if ($pkg.mode) { $pkg.mode } else { "installable" }
                    Device = $device.FriendlyName
                    InstanceId = $device.InstanceId
                    MatchedIds = $matchedIds
                    Package = $pkg
                }
            }
        }
    }

    return $matches | Sort-Object InstallOrder, Risk, Vendor, Title
}

function Save-Package {
    param($Match)

    if (-not $Match.Url) {
        throw "Package '$($Match.Id)' has no URL."
    }
    if (-not $Match.Sha256) {
        throw "Package '$($Match.Id)' has no SHA256."
    }

    New-Item -ItemType Directory -Force -Path $PackageCache | Out-Null
    $fileName = Split-Path -Path ([uri]$Match.Url).AbsolutePath -Leaf
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = "$($Match.Id).zip"
    }
    $destination = Join-Path $PackageCache $fileName

    if (-not (Test-Path -LiteralPath $destination)) {
        if (-not $OnlineDownload) {
            throw "Package '$($Match.Id)' is not cached at $destination. Pass -OnlineDownload to download it."
        }
        Invoke-WebRequest -Uri $Match.Url -OutFile $destination
    }

    $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne ([string]$Match.Sha256).ToLowerInvariant()) {
        throw "SHA256 mismatch for '$($Match.Id)'. Expected $($Match.Sha256), got $hash."
    }

    return $destination
}

function Install-InfPackage {
    param([string]$ZipPath, [string]$PackageId)

    $extractRoot = Join-Path $PackageCache "expanded-$PackageId"
    if (Test-Path -LiteralPath $extractRoot) {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $extractRoot -Force

    $infFiles = @(Get-ChildItem -LiteralPath $extractRoot -Filter *.inf -Recurse -File)
    if ($infFiles.Count -eq 0) {
        throw "No INF files found in $ZipPath."
    }

    $arguments = @("/add-driver", (Join-Path $extractRoot "*.inf"), "/subdirs", "/install")
    Write-Host "pnputil $($arguments -join ' ')"
    & pnputil @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "pnputil failed for '$PackageId' with exit code $LASTEXITCODE."
    }
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
Write-Section "Enumerating devices"
$devices = Get-DeviceHardwareIds
Write-Host "Found $($devices.Count) present devices."

Write-Section "Matching packages"
$matches = @(Get-PackageMatches -Manifest $manifest -Devices $devices)
if ($matches.Count -eq 0) {
    Write-Host "No package matches found."
    return
}

$matches | Select-Object InstallOrder, Id, Title, Vendor, Category, Risk, Device, MatchedIds | Format-Table -AutoSize

if (-not $Apply) {
    Write-Host "Dry run only. Re-run with -Apply to install matched packages."
    return
}

Write-Section "Installing matched packages"
foreach ($match in $matches) {
    if ($match.Mode -eq "advisory_only") {
        Write-Warning "Skipping advisory-only package '$($match.Id)': $($match.Title)"
        continue
    }

    if ($PSCmdlet.ShouldProcess($match.Id, "download, verify, expand, and install INF driver package")) {
        try {
            $zipPath = Save-Package -Match $match
            Install-InfPackage -ZipPath $zipPath -PackageId $match.Id
        } catch {
            Write-Warning "Failed to install '$($match.Id)': $($_.Exception.Message)"
        }
    }
}
