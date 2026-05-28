[CmdletBinding()]
param(
    [string]$SourcePath = "driver_packages.json",
    [string]$OutputPath = "manifest.generated.json",
    [string]$Repository = "https://github.com/TheOneAdonis/qudong",
    [string]$Release = "v1.1.0",
    [string]$VersionSuffix = "generated"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-OrderedPackage {
    param($Package)

    $ordered = [ordered]@{}
    $preferredOrder = @(
        "id", "mode", "url", "version", "sha256", "category", "vendor", "title",
        "priority", "score", "confidence", "success_rate", "risk", "signed", "whql",
        "reboot_required", "installOrder", "verify", "rollback", "depends", "conflicts",
        "hwids", "os", "deviceClass", "install_type", "source", "catalog_fallback",
        "local_only", "note", "advisory", "win10_preferred"
    )

    foreach ($name in $preferredOrder) {
        if ($Package.PSObject.Properties.Name.Contains($name)) {
            $ordered[$name] = $Package.$name
        }
    }

    foreach ($property in ($Package.PSObject.Properties | Sort-Object Name)) {
        if (-not $ordered.Contains($property.Name)) {
            $ordered[$property.Name] = $property.Value
        }
    }

    if (-not $ordered.Contains("mode")) {
        if ($ordered.Contains("url") -and $null -ne $ordered["url"] -and $ordered["url"] -ne "" -and $ordered.Contains("sha256") -and $null -ne $ordered["sha256"] -and $ordered["sha256"] -ne "") {
            $ordered.Insert(1, "mode", "installable")
        } else {
            $ordered.Insert(1, "mode", "advisory_only")
        }
    }

    return $ordered
}

if (-not (Test-Path -LiteralPath $SourcePath)) {
    throw "Source manifest not found: $SourcePath"
}

$source = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
if ($null -eq $source.packages) {
    throw "Source manifest has no packages object."
}

$packages = [ordered]@{}
foreach ($packageProperty in ($source.packages.PSObject.Properties | Sort-Object Name)) {
    $packages[$packageProperty.Name] = ConvertTo-OrderedPackage $packageProperty.Value
}

$manifest = [ordered]@{
    schema_version = if ($source.schema_version) { $source.schema_version } else { 3 }
    version = if ($VersionSuffix) { "$($source.version)-$VersionSuffix" } else { $source.version }
    updated = (Get-Date -Format "yyyy-MM-dd")
    description = "Qudong generated driver manifest"
    repository = $Repository
    release = $Release
    mirrors = @("github")
    packages = $packages
    target_os = if ($source.target_os) { $source.target_os } else { @("win10", "win11") }
    primary_os = if ($source.primary_os) { $source.primary_os } else { "win10" }
    min_os_build = if ($source.min_os_build) { $source.min_os_build } else { 10240 }
}

$json = $manifest | ConvertTo-Json -Depth 100
Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8
Write-Host "Generated $OutputPath from $SourcePath"
