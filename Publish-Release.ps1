#requires -Version 5.1
# Build ZIPs, refresh manifest sha256, upload to GitHub Release, push manifest
param(
    [string]$Tag = 'v1.0.0',
    [string]$Repo = 'yanbai9188-oss/qudong',
    [switch]$SkipUpload,
    [switch]$SkipPush
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$manifestPath = Join-Path $root 'driver_packages.json'
$pkgScript = Join-Path $PSScriptRoot 'Build-ReleasePackages.ps1'

Write-Host '=== Build release packages ===' -ForegroundColor Cyan
& $pkgScript

$packagesDir = Join-Path $PSScriptRoot 'packages'
$hashByZip = @{}
Get-ChildItem $packagesDir -Filter '*.zip' | ForEach-Object {
    $hashByZip[$_.Name] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
}

$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$updated = 0
foreach ($prop in $manifest.packages.PSObject.Properties) {
    $pkg = $prop.Value
    if (-not $pkg.url) { continue }
    $zipName = [IO.Path]::GetFileName($pkg.url)
    if ($hashByZip.ContainsKey($zipName)) {
        $newHash = $hashByZip[$zipName]
        if ($pkg.sha256 -ne $newHash) {
            $pkg.sha256 = $newHash
            $updated++
        }
    }
}
$manifest.updated = (Get-Date -Format 'yyyy-MM-dd')
($manifest | ConvertTo-Json -Depth 12) | Set-Content $manifestPath -Encoding UTF8
Copy-Item $manifestPath (Join-Path $PSScriptRoot 'manifest.json') -Force
Copy-Item $manifestPath (Join-Path $PSScriptRoot 'driver_packages.json') -Force
Write-Host "Manifest sha256 updated: $updated package(s)" -ForegroundColor Green

if ($SkipUpload) {
    Write-Host 'SkipUpload set; done.'
    exit 0
}

Write-Host '=== Upload to GitHub Release ===' -ForegroundColor Cyan
$input = "protocol=https`nhost=github.com`n`n"
$credOut = $input | git credential fill 2>&1 | Out-String
$token = ($credOut -split "`n" | Where-Object { $_ -like 'password=*' }) -replace 'password=',''
if (-not $token) { throw 'No GitHub token from git credential helper' }

$headers = @{
    Authorization = "Bearer $token"
    Accept        = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}

try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag" -Headers $headers
} catch {
    $body = @{
        tag_name = $Tag
        name     = "$Tag - CIODIY Driver Pack"
        body     = 'CIODIY driver package release.'
        draft    = $false
        prerelease = $false
    } | ConvertTo-Json
    $rel = Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/$Repo/releases" -Headers $headers -Body $body -ContentType 'application/json; charset=utf-8'
}

$releaseId = $rel.id
$existing = @{}
foreach ($a in @($rel.assets)) { $existing[$a.name] = $a.id }

$toUpload = New-Object System.Collections.Generic.List[string]
foreach ($prop in $manifest.packages.PSObject.Properties) {
    $zipName = [IO.Path]::GetFileName($prop.Value.url)
    if ($zipName -and -not $existing.ContainsKey($zipName)) {
        [void]$toUpload.Add($zipName)
    }
}
# Also upload extra built zips referenced by manifest id map
foreach ($zipName in @('intel_bluetooth_7260.zip', 'realtek_lan_8168.zip')) {
    if ($hashByZip.ContainsKey($zipName) -and -not $existing.ContainsKey($zipName) -and ($toUpload -notcontains $zipName)) {
        [void]$toUpload.Add($zipName)
    }
}

foreach ($zipName in ($toUpload | Sort-Object -Unique)) {
    $zipPath = Join-Path $packagesDir $zipName
    if (-not (Test-Path $zipPath)) {
        Write-Host "  skip missing: $zipName" -ForegroundColor Yellow
        continue
    }
    $mb = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Host "  uploading: $zipName ($mb MB)..."
    $uploadUrl = "https://uploads.github.com/repos/$Repo/releases/$releaseId/assets?name=$zipName"
    $uploadHeaders = @{
        Authorization = "Bearer $token"
        Accept        = 'application/vnd.github+json'
        'Content-Type' = 'application/zip'
    }
    Invoke-RestMethod -Method Post -Uri $uploadUrl -Headers $uploadHeaders -InFile $zipPath | Out-Null
    Write-Host "  done: $zipName"
}

if ($SkipPush) {
    Write-Host 'SkipPush set; upload done.'
    exit 0
}

Write-Host '=== Push manifest to GitHub ===' -ForegroundColor Cyan
Push-Location $PSScriptRoot
git add manifest.json driver_packages.json Build-ReleasePackages.ps1 Publish-Release.ps1
$status = git status --porcelain
if ($status) {
    git commit -m "Update manifest sha256 and publish release $Tag"
    git push origin main
    Write-Host 'Manifest pushed.' -ForegroundColor Green
} else {
    Write-Host 'No manifest changes to push.'
}
Pop-Location
Write-Host 'Publish complete.' -ForegroundColor Green
