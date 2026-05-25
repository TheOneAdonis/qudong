#requires -Version 5.1
# Build ZIP packages from Drivers\ for GitHub Release upload
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$drivers = Join-Path $root 'Drivers'
$out = Join-Path $PSScriptRoot 'packages'
New-Item -ItemType Directory -Force -Path $out | Out-Null

$map = @{
    'intel_wifi'        = 'intel_wifi'
    'intel_chipset'     = 'intel_chipset'
    'intel_bluetooth'   = 'intel_bluetooth'
    'intel_mei'         = 'intel_mei'
    'intel_sst'         = 'intel_sst'
    'intel_dtt'         = 'intel_dtt'
    'intel_platform'    = 'intel_platform'
    'intel_serialio'    = 'intel_serialio'
    'intel_rst'         = 'intel_rst'
    'realtek_lan'       = 'realtek_lan'
    'realtek_audio'     = 'realtek_audio'
    'amd_chipset'       = 'amd_chipset'
    'Intel_7260_WiFi_16.10.0.5' = 'intel_wifi_7260'
    'Intel_7260_Bluetooth_20.100.5.1' = 'intel_bluetooth_7260'
    'Realtek_LAN_8168'  = 'realtek_lan_8168'
    'intel_graphics'    = 'intel_graphics'
    'intel_usb3'        = 'intel_usb3'
    'intel_lan_i219'    = 'intel_lan_i219'
    'intel_wifi_8260'   = 'intel_wifi_8260'
    'realtek_cardreader' = 'realtek_cardreader'
    'Intel_DisplayAudio' = 'intel_display_audio'
    'nvidia_dch_gpu'     = 'nvidia_dch_gpu'
    'synaptics_touchpad' = 'synaptics_touchpad'
    'elan_touchpad'      = 'elan_touchpad'
    'hp_printer_pcl'     = 'hp_printer_pcl'
    'canon_printer_ufrii' = 'canon_printer_ufrii'
}

Write-Host 'Building release ZIPs...'
foreach ($folder in $map.Keys) {
    $src = Join-Path $drivers $folder
    if (-not (Test-Path $src)) {
        Write-Host "  skip missing: $folder"
        continue
    }
    Get-ChildItem $src -Filter 'catalog_driver.cab' -Recurse -EA SilentlyContinue | Remove-Item -Force -EA SilentlyContinue
    $infCount = @(Get-ChildItem $src -Filter '*.inf' -Recurse -EA SilentlyContinue).Count
    if ($infCount -eq 0) {
        Write-Host "  skip no inf: $folder"
        continue
    }
    $zipName = $map[$folder] + '.zip'
    $zipPath = Join-Path $out $zipName
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $src '*') -DestinationPath $zipPath -Force
    $hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
    Write-Host ("  {0,-28} sha256={1}" -f $zipName, $hash)
}

Copy-Item (Join-Path $root 'driver_packages.json') (Join-Path $PSScriptRoot 'manifest.json') -Force
Write-Host "`nPackages: $out"
Write-Host "Upload: Publish-Release.ps1 -Tag v1.1.0"
