param(
    [Parameter(Mandatory = $true)]
    [string]$ItemId,
    [string]$ConfigPath = (Join-Path $PSScriptRoot "..\config.json"),
    [string]$JobId = "",
    [switch]$SkipManifest
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string]$Path) {
    $executionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Assert-SafeItemId([string]$Value) {
    if ($Value -notmatch "^[A-Za-z0-9._-]+$") {
        throw "Invalid item id. Only letters, numbers, dot, underscore, and dash are allowed."
    }
}

function Write-JobState([string]$State, [string]$Message = "", [string]$LogPath = "") {
    if ([string]::IsNullOrWhiteSpace($JobId)) { return }

    $jobsDir = Join-Path $script:LibraryRoot "jobs"
    if (-not (Test-Path $jobsDir)) {
        New-Item -ItemType Directory -Path $jobsDir | Out-Null
    }

    $payload = [ordered]@{
        jobId = $JobId
        itemId = $ItemId
        state = $State
        message = $Message
        logPath = $LogPath
        updatedAt = (Get-Date).ToUniversalTime().ToString("o")
    }
    $payload | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -Path (Join-Path $jobsDir "$JobId.json")
}

function Find-PackageInput([string]$PackagesRoot, [string]$ItemId) {
    $directDir = Join-Path $PackagesRoot $ItemId
    if (Test-Path $directDir) {
        $pkg = Get-ChildItem -Path $directDir -Recurse -File -Filter "*.pkg" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pkg) { return $pkg.FullName }
        return $directDir
    }

    $directPkg = Join-Path $PackagesRoot "$ItemId.pkg"
    if (Test-Path $directPkg) { return $directPkg }

    throw "Could not find package input for item '$ItemId' under $PackagesRoot"
}

Assert-SafeItemId $ItemId

if (-not (Test-Path $ConfigPath)) {
    throw "Config not found: $ConfigPath"
}

$config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
$script:LibraryRoot = Resolve-FullPath $config.libraryRoot
$packagesRoot = Join-Path $script:LibraryRoot "packages"
$extractedRoot = Join-Path $script:LibraryRoot "extracted"
$logsRoot = Join-Path $script:LibraryRoot "logs"

foreach ($dir in @($extractedRoot, $logsRoot)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

$repkgPath = Resolve-FullPath $config.repkgPath
if (-not (Test-Path $repkgPath)) {
    throw "RePKG executable not found: $repkgPath"
}

$inputPath = Find-PackageInput -PackagesRoot $packagesRoot -ItemId $ItemId
$outputPath = Join-Path $extractedRoot $ItemId
$logPath = Join-Path $logsRoot "$ItemId-repkg.log"

if (-not (Test-Path $outputPath)) {
    New-Item -ItemType Directory -Path $outputPath | Out-Null
}

Write-JobState -State "running" -Message "Extracting with RePKG" -LogPath $logPath

try {
    $arguments = @("extract", "--overwrite", "-c", "-o", $outputPath, $inputPath)
    "RePKG command: `"$repkgPath`" $($arguments -join " ")" | Set-Content -Encoding UTF8 -Path $logPath
    & $repkgPath @arguments *>> $logPath

    if ($LASTEXITCODE -ne 0) {
        throw "RePKG exited with code $LASTEXITCODE. See $logPath"
    }

    if (-not $SkipManifest) {
        & (Join-Path $PSScriptRoot "Generate-LibraryManifest.ps1") -ConfigPath $ConfigPath *>> $logPath
    }

    Write-JobState -State "done" -Message "Unpack complete" -LogPath $logPath
    Write-Host "Unpacked $ItemId to $outputPath"
} catch {
    Write-JobState -State "failed" -Message $_.Exception.Message -LogPath $logPath
    throw
}
