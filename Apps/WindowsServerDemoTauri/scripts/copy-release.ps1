$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Resolve-Path (Join-Path $scriptDir "..")
$repoRoot = Resolve-Path (Join-Path $appRoot "..\..")
$bundleDir = Join-Path $appRoot "src-tauri\target\release\bundle"
$releaseDir = Join-Path $repoRoot "release\windows-tauri"

if (-not (Test-Path -LiteralPath $bundleDir)) {
    throw "Tauri bundle directory not found: $bundleDir"
}

$resolvedRepoRoot = [System.IO.Path]::GetFullPath($repoRoot.Path)
$resolvedReleaseDir = [System.IO.Path]::GetFullPath($releaseDir)
if (-not $resolvedReleaseDir.StartsWith($resolvedRepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to write outside repository root: $resolvedReleaseDir"
}

if (Test-Path -LiteralPath $releaseDir) {
    Remove-Item -LiteralPath $releaseDir -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
Copy-Item -Path (Join-Path $bundleDir "*") -Destination $releaseDir -Recurse -Force

Write-Host "Windows Tauri release artifacts copied to: $releaseDir"
