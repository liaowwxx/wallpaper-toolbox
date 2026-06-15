param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "..\config.json")
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string]$Path) {
    $executionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

if (-not (Test-Path $ConfigPath)) {
    throw "Config not found: $ConfigPath. Run Initialize-WallpaperLibrary.ps1 first."
}

$config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
$root = Resolve-FullPath $config.libraryRoot
$miniservePath = Resolve-FullPath $config.miniservePath

if (-not (Test-Path $miniservePath)) {
    throw "miniserve executable not found: $miniservePath"
}

if (-not (Test-Path (Join-Path $root "library.json"))) {
    & (Join-Path $PSScriptRoot "Generate-LibraryManifest.ps1") -ConfigPath $ConfigPath
}

$bindAddress = if ($config.bindAddress) { [string]$config.bindAddress } else { "0.0.0.0" }
$staticPort = if ($config.staticPort) { [int]$config.staticPort } else { 8080 }
$args = @("-i", $bindAddress, "-p", "$staticPort", "-q", "-P", "--header", "Cache-Control:no-cache")

if ($config.authUser -and $config.authPassword) {
    $args += @("--auth", "$($config.authUser):$($config.authPassword)")
}

$args += $root

Write-Host "Starting miniserve:"
Write-Host "`"$miniservePath`" $($args -join " ")"
& $miniservePath @args
