[CmdletBinding()]
param(
    [string]$ManifestPath = "manifest.json",
    [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Add-Finding {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        [string]$Level,
        [string]$Code,
        [string]$Message,
        [string]$PackageKey = ""
    )

    $Findings.Add([pscustomobject]@{
        level = $Level
        code = $Code
        package = $PackageKey
        message = $Message
    }) | Out-Null
}

function Test-Mojibake {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    return $Text -match "鑺|鎵|椹|甯|噺|缁|卞|嵃||\?"
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

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}

$raw = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
try {
    $manifest = $raw | ConvertFrom-Json -Depth 100
} catch {
    throw "Invalid JSON in $ManifestPath. $($_.Exception.Message)"
}

$findings = [System.Collections.Generic.List[object]]::new()

foreach ($requiredRoot in @("schema_version", "version", "updated", "packages", "target_os")) {
    if (-not $manifest.PSObject.Properties.Name.Contains($requiredRoot)) {
        Add-Finding $findings "error" "root.missing" "Missing required root field '$requiredRoot'."
    }
}

if ($null -eq $manifest.packages) {
    Add-Finding $findings "error" "packages.missing" "Manifest has no packages object."
} else {
    $ids = @{}
    $packageNames = @($manifest.packages.PSObject.Properties.Name)

    foreach ($packageKey in $packageNames) {
        $pkg = $manifest.packages.$packageKey
        $requiredFields = @("id", "title", "vendor", "category", "deviceClass", "version", "os", "hwids", "risk", "signed", "whql", "reboot_required")

        foreach ($field in $requiredFields) {
            if (-not $pkg.PSObject.Properties.Name.Contains($field) -or $null -eq $pkg.$field -or (($pkg.$field -is [string]) -and [string]::IsNullOrWhiteSpace($pkg.$field))) {
                Add-Finding $findings "error" "package.required" "Missing required field '$field'." $packageKey
            }
        }

        if ($pkg.id) {
            if ($ids.ContainsKey($pkg.id)) {
                Add-Finding $findings "error" "package.duplicate_id" "Duplicate id '$($pkg.id)' also used by '$($ids[$pkg.id])'." $packageKey
            } else {
                $ids[$pkg.id] = $packageKey
            }
        }

        if ($pkg.sha256 -and ($pkg.sha256 -notmatch "^[A-Fa-f0-9]{64}$")) {
            Add-Finding $findings "error" "package.sha256_format" "sha256 must be 64 hex characters." $packageKey
        }

        $isAdvisory = ($pkg.mode -eq "advisory_only") -or ($pkg.catalog_fallback -eq $true) -or ($pkg.local_only -eq $true)
        if (-not $isAdvisory) {
            if ($null -eq $pkg.url -or [string]::IsNullOrWhiteSpace([string]$pkg.url)) {
                Add-Finding $findings "warning" "package.url_missing" "Installable package has no URL. Mark as advisory_only or provide a downloadable URL." $packageKey
            }
            if ($null -eq $pkg.sha256 -or [string]::IsNullOrWhiteSpace([string]$pkg.sha256)) {
                Add-Finding $findings "warning" "package.sha256_missing" "Installable package has no sha256. Mark as advisory_only or provide a hash." $packageKey
            }
        }

        if (Test-Mojibake ([string]$pkg.title)) {
            Add-Finding $findings "warning" "package.mojibake" "Title looks mojibake/corrupted: '$($pkg.title)'." $packageKey
        }

        $hwids = Normalize-Array $pkg.hwids
        if ($hwids.Count -eq 0) {
            Add-Finding $findings "error" "package.hwids_empty" "Package must contain at least one hardware id." $packageKey
        }
        foreach ($hwid in $hwids) {
            if ([string]$hwid -notmatch "^(PCI|USB|HDAUDIO|HID|ACPI|SWD|ROOT|DISPLAY|BTH)\\") {
                Add-Finding $findings "warning" "package.hwid_format" "Unexpected HWID prefix: '$hwid'." $packageKey
            }
        }

        if ($pkg.depends) {
            foreach ($dep in (Normalize-Array $pkg.depends)) {
                if (-not $ids.ContainsKey([string]$dep) -and -not ($packageNames | Where-Object { $_ -eq $dep })) {
                    Add-Finding $findings "warning" "package.depends_missing" "Dependency '$dep' is not present in this manifest." $packageKey
                }
            }
        }

        if ($pkg.conflicts) {
            foreach ($conflict in (Normalize-Array $pkg.conflicts)) {
                if (-not $ids.ContainsKey([string]$conflict) -and -not ($packageNames | Where-Object { $_ -eq $conflict })) {
                    Add-Finding $findings "warning" "package.conflict_missing" "Conflict reference '$conflict' is not present in this manifest." $packageKey
                }
            }
        }

        if (($pkg.category -match "touch|input" -or $pkg.title -match "TouchPad|触摸板") -and $pkg.deviceClass -match "network") {
            Add-Finding $findings "warning" "package.deviceclass_suspicious" "Input/touchpad package has network-like deviceClass '$($pkg.deviceClass)'." $packageKey
        }
    }
}

$errorCount = @($findings | Where-Object { $_.level -eq "error" }).Count
$warningCount = @($findings | Where-Object { $_.level -eq "warning" }).Count

$result = [pscustomobject]@{
    manifest = $ManifestPath
    errors = $errorCount
    warnings = $warningCount
    findings = $findings
}

$result | ConvertTo-Json -Depth 10

if ($errorCount -gt 0 -or ($Strict -and $warningCount -gt 0)) {
    exit 1
}
