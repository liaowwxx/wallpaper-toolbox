param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "..\config.json"),
    [string]$LibraryRoot = ""
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string]$Path) {
    $executionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

$demoRoot = Resolve-FullPath (Join-Path $PSScriptRoot "..")
$exampleConfigPath = Join-Path $demoRoot "config.example.json"

if (-not (Test-Path $ConfigPath)) {
    Copy-Item -Path $exampleConfigPath -Destination $ConfigPath
    Write-Host "Created config: $ConfigPath"
}

$config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
if (-not [string]::IsNullOrWhiteSpace($LibraryRoot)) {
    $config.libraryRoot = $LibraryRoot
    $config | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -Path $ConfigPath
}

$root = Resolve-FullPath $config.libraryRoot
$dirs = @(
    $root,
    (Join-Path $root "packages"),
    (Join-Path $root "extracted"),
    (Join-Path $root "thumbs"),
    (Join-Path $root "jobs"),
    (Join-Path $root "logs")
)

foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

$manifestPath = Join-Path $root "library.json"
if (-not (Test-Path $manifestPath)) {
    Copy-Item -Path (Join-Path $demoRoot "samples\library.sample.json") -Destination $manifestPath
}

Write-Host "Wallpaper library initialized at: $root"
Write-Host "Place Wallpaper Engine workshop folders or .pkg files in: $(Join-Path $root "packages")"
