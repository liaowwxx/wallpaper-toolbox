param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "..\config.json")
)

$ErrorActionPreference = "Stop"

$ImageExtensions = @(".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp", ".tiff", ".tif", ".heic", ".heif")
$VideoExtensions = @(".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v", ".wmv", ".flv", ".mpg", ".mpeg")

function Resolve-FullPath([string]$Path) {
    $executionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Get-Config {
    if (-not (Test-Path $ConfigPath)) {
        throw "Config not found: $ConfigPath. Run Initialize-WallpaperLibrary.ps1 first."
    }
    Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
}

function ConvertTo-UrlPath([string]$RelativePath) {
    $parts = $RelativePath -split "[\\/]+" | Where-Object { $_ -ne "" }
    ($parts | ForEach-Object { [uri]::EscapeDataString($_) }) -join "/"
}

function Get-ProjectJson([string]$Directory) {
    $projectPath = Join-Path $Directory "project.json"
    if (Test-Path $projectPath) {
        try {
            return Get-Content -Raw -Path $projectPath | ConvertFrom-Json
        } catch {
            Write-Warning "Failed to parse project.json: $projectPath"
        }
    }
    return $null
}

function Get-PreviewFile([string]$Directory) {
    if (-not (Test-Path $Directory)) { return $null }

    $preferred = Get-ChildItem -Path $Directory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match "^preview" -and $ImageExtensions -contains $_.Extension.ToLowerInvariant() } |
        Select-Object -First 1

    if ($preferred) { return $preferred }

    Get-ChildItem -Path $Directory -File -ErrorAction SilentlyContinue |
        Where-Object { $ImageExtensions -contains $_.Extension.ToLowerInvariant() } |
        Select-Object -First 1
}

function Get-AssetKind([string]$Path) {
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($ImageExtensions -contains $ext) { return "image" }
    if ($VideoExtensions -contains $ext) { return "video" }
    return $null
}

function Get-MediaAssets([string]$ItemId, [string]$ExtractedDir) {
    if (-not (Test-Path $ExtractedDir)) { return @() }

    $root = (Resolve-Path $ExtractedDir).Path.TrimEnd("\", "/")
    $assets = New-Object System.Collections.Generic.List[object]

    Get-ChildItem -Path $ExtractedDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        $kind = Get-AssetKind $_.FullName
        if ($kind) {
            $relative = $_.FullName.Substring($root.Length).TrimStart("\", "/")
            $urlRelative = ConvertTo-UrlPath $relative
            $assetIdSuffix = ($relative -replace "[^A-Za-z0-9._-]+", "-").Trim("-")

            $assets.Add([ordered]@{
                id = "$ItemId-$assetIdSuffix"
                name = $_.Name
                kind = $kind
                url = "/extracted/$(ConvertTo-UrlPath $ItemId)/$urlRelative"
                size = $_.Length
            })
        }
    }

    @($assets | Sort-Object @{ Expression = { if ($_.kind -eq "video") { 0 } else { 1 } } }, name)
}

function New-Thumbnail([string]$ItemId, [object]$PreviewFile, [array]$Assets, [string]$ThumbsDir, [string]$ExtractedRoot) {
    if (-not (Test-Path $ThumbsDir)) {
        New-Item -ItemType Directory -Path $ThumbsDir | Out-Null
    }

    if ($PreviewFile) {
        $ext = $PreviewFile.Extension.ToLowerInvariant()
        $dest = Join-Path $ThumbsDir "$ItemId$ext"
        if (-not (Test-Path $dest) -or $PreviewFile.LastWriteTimeUtc -gt (Get-Item $dest).LastWriteTimeUtc) {
            Copy-Item -Path $PreviewFile.FullName -Destination $dest -Force
        }
        return "/thumbs/$(ConvertTo-UrlPath "$ItemId$ext")"
    }

    $video = $Assets | Where-Object { $_.kind -eq "video" } | Select-Object -First 1
    if ($video) {
        $ffmpeg = Get-Command "ffmpeg" -ErrorAction SilentlyContinue
        if ($ffmpeg) {
            $relative = ($video.url -replace "^/extracted/[^/]+/", "") -replace "/", [System.IO.Path]::DirectorySeparatorChar
            $source = Join-Path (Join-Path $ExtractedRoot $ItemId) $relative
            $dest = Join-Path $ThumbsDir "$ItemId.jpg"
            if (-not (Test-Path $dest)) {
                & $ffmpeg.Source -y -ss 00:00:01 -i $source -vframes 1 -vf "scale=512:-1" $dest 2>$null | Out-Null
            }
            if (Test-Path $dest) {
                return "/thumbs/$(ConvertTo-UrlPath "$ItemId.jpg")"
            }
        }
    }

    return $null
}

function Read-StringArray($Value) {
    if ($null -eq $Value) { return @() }
    if ($Value -is [array]) { return @($Value | Where-Object { $_ }) }
    return @($Value)
}

function Get-PackageIndex([string]$PackagesRoot) {
    $index = @{}
    if (-not (Test-Path $PackagesRoot)) { return $index }

    Get-ChildItem -Path $PackagesRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $id = $_.Name
        $pkg = Get-ChildItem -Path $_.FullName -Recurse -File -Filter "*.pkg" -ErrorAction SilentlyContinue | Select-Object -First 1
        $index[$id] = [ordered]@{
            id = $id
            packagePath = if ($pkg) { $pkg.FullName } else { $null }
            packageDir = $_.FullName
            project = Get-ProjectJson $_.FullName
            preview = Get-PreviewFile $_.FullName
        }
    }

    Get-ChildItem -Path $PackagesRoot -File -Filter "*.pkg" -ErrorAction SilentlyContinue | ForEach-Object {
        $id = $_.BaseName
        if (-not $index.ContainsKey($id)) {
            $index[$id] = [ordered]@{
                id = $id
                packagePath = $_.FullName
                packageDir = $_.DirectoryName
                project = Get-ProjectJson $_.DirectoryName
                preview = Get-PreviewFile $_.DirectoryName
            }
        }
    }

    $index
}

$config = Get-Config
$root = Resolve-FullPath $config.libraryRoot
$packagesRoot = Join-Path $root "packages"
$extractedRoot = Join-Path $root "extracted"
$thumbsRoot = Join-Path $root "thumbs"
$manifestPath = Join-Path $root "library.json"

foreach ($dir in @($root, $packagesRoot, $extractedRoot, $thumbsRoot)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

$packageIndex = Get-PackageIndex $packagesRoot
$ids = New-Object System.Collections.Generic.HashSet[string]
$packageIndex.Keys | ForEach-Object { [void]$ids.Add($_) }

if (Test-Path $extractedRoot) {
    Get-ChildItem -Path $extractedRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        [void]$ids.Add($_.Name)
    }
}

$items = New-Object System.Collections.Generic.List[object]

foreach ($id in ($ids | Sort-Object)) {
    $entry = $packageIndex[$id]
    $project = if ($entry) { $entry.project } else { $null }
    $preview = if ($entry) { $entry.preview } else { $null }
    $extractedDir = Join-Path $extractedRoot $id
    $assets = @(Get-MediaAssets -ItemId $id -ExtractedDir $extractedDir)

    $type = "unknown"
    if ($project -and $project.type) {
        $type = [string]$project.type
    } elseif ($assets | Where-Object { $_.kind -eq "video" } | Select-Object -First 1) {
        $type = "video"
    } elseif ($assets | Where-Object { $_.kind -eq "image" } | Select-Object -First 1) {
        $type = "image"
    }

    $title = $id
    if ($project -and $project.title) {
        $title = [string]$project.title
    }

    $thumbnail = New-Thumbnail -ItemId $id -PreviewFile $preview -Assets $assets -ThumbsDir $thumbsRoot -ExtractedRoot $extractedRoot

    $items.Add([ordered]@{
        id = $id
        title = $title
        type = $type
        thumbnail = $thumbnail
        isUnpacked = ($assets.Count -gt 0)
        tags = @(Read-StringArray $(if ($project) { $project.preview_tagger } else { $null }))
        collections = @(Read-StringArray $(if ($project) { $project.repkgcollection } else { $null }))
        assets = @($assets)
    })
}

$features = @("rangeStreaming", "staticManifest", "unpackJobs", "thumbnails")
if ($config.features) {
    $features = @($config.features)
}

$manifest = [ordered]@{
    schemaVersion = 1
    serverVersion = if ($config.serverVersion) { $config.serverVersion } else { "0.1.0-demo" }
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    features = $features
    items = @($items)
}

$manifest | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -Path $manifestPath
Write-Host "Wrote $($items.Count) items to $manifestPath"
