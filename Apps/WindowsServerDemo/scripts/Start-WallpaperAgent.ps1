param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "..\config.json")
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string]$Path) {
    $executionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Assert-SafeItemId([string]$Value) {
    if ($Value -notmatch "^[A-Za-z0-9._-]+$") {
        throw "Invalid item id."
    }
}

function ConvertTo-JsonBytes($Value, [int]$StatusCode = 200) {
    $json = $Value | ConvertTo-Json -Depth 12
    [System.Text.Encoding]::UTF8.GetBytes($json)
}

function Send-Json($Context, $Value, [int]$StatusCode = 200) {
    $bytes = ConvertTo-JsonBytes $Value $StatusCode
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = "application/json; charset=utf-8"
    $Context.Response.Headers["Access-Control-Allow-Origin"] = "*"
    $Context.Response.Headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS"
    $Context.Response.Headers["Access-Control-Allow-Headers"] = "Authorization,Content-Type"
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.Close()
}

function Send-FileJson($Context, [string]$Path) {
    if (-not (Test-Path $Path)) {
        Send-Json $Context ([ordered]@{ error = "Not found" }) 404
        return
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $Context.Response.StatusCode = 200
    $Context.Response.ContentType = "application/json; charset=utf-8"
    $Context.Response.Headers["Access-Control-Allow-Origin"] = "*"
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.Close()
}

function Test-Authorized($Context) {
    if (-not $script:Config.authUser -or -not $script:Config.authPassword) {
        return $true
    }

    $header = $Context.Request.Headers["Authorization"]
    if (-not $header -or -not $header.StartsWith("Basic ")) {
        $Context.Response.StatusCode = 401
        $Context.Response.Headers["WWW-Authenticate"] = "Basic realm=`"Wallpaper Agent`""
        $Context.Response.Close()
        return $false
    }

    $encoded = $header.Substring(6)
    try {
        $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
    } catch {
        Send-Json $Context ([ordered]@{ error = "Unauthorized" }) 401
        return $false
    }
    $expected = "$($script:Config.authUser):$($script:Config.authPassword)"
    if ($decoded -ne $expected) {
        Send-Json $Context ([ordered]@{ error = "Unauthorized" }) 401
        return $false
    }
    return $true
}

function Read-Manifest {
    $path = Join-Path $script:LibraryRoot "library.json"
    if (-not (Test-Path $path)) {
        & (Join-Path $PSScriptRoot "Generate-LibraryManifest.ps1") -ConfigPath $script:ConfigPath
    }
    Get-Content -Raw -Path $path | ConvertFrom-Json
}

function Read-JobFile([string]$JobId) {
    Assert-SafeItemId $JobId
    $path = Join-Path (Join-Path $script:LibraryRoot "jobs") "$JobId.json"
    if (-not (Test-Path $path)) { return $null }
    Get-Content -Raw -Path $path | ConvertFrom-Json
}

function Write-JobFile([string]$JobId, [string]$ItemId, [string]$State, [string]$Message) {
    $jobsDir = Join-Path $script:LibraryRoot "jobs"
    if (-not (Test-Path $jobsDir)) {
        New-Item -ItemType Directory -Path $jobsDir | Out-Null
    }
    [ordered]@{
        jobId = $JobId
        itemId = $ItemId
        state = $State
        message = $Message
        updatedAt = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -Path (Join-Path $jobsDir "$JobId.json")
}

function Update-RunningJob {
    if ($null -ne $script:RunningJob -and $script:RunningJob.State -ne "Running") {
        Receive-Job -Job $script:RunningJob -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $script:RunningJob -Force -ErrorAction SilentlyContinue
        $script:RunningJob = $null
        $script:RunningJobId = ""
    }
}

function Start-NextQueuedJob {
    Update-RunningJob
    if ($null -ne $script:RunningJob) { return }
    if ($script:Queue.Count -eq 0) { return }

    $queued = $script:Queue.Dequeue()
    Write-JobFile -JobId $queued.jobId -ItemId $queued.itemId -State "running" -Message "Queued job started"
    $script:RunningJobId = $queued.jobId
    $script:RunningJob = Start-Job -ScriptBlock {
        param($ScriptRoot, $ConfigPath, $ItemId, $JobId)
        & (Join-Path $ScriptRoot "Invoke-RePKGUnpack.ps1") -ConfigPath $ConfigPath -ItemId $ItemId -JobId $JobId
    } -ArgumentList $PSScriptRoot, $script:ConfigPath, $queued.itemId, $queued.jobId
}

if (-not (Test-Path $ConfigPath)) {
    throw "Config not found: $ConfigPath. Run Initialize-WallpaperLibrary.ps1 first."
}

$script:ConfigPath = Resolve-FullPath $ConfigPath
$script:Config = Get-Content -Raw -Path $script:ConfigPath | ConvertFrom-Json
$script:LibraryRoot = Resolve-FullPath $script:Config.libraryRoot
$script:Queue = New-Object System.Collections.Queue
$script:RunningJob = $null
$script:RunningJobId = ""

if (-not (Test-Path (Join-Path $script:LibraryRoot "library.json"))) {
    & (Join-Path $PSScriptRoot "Generate-LibraryManifest.ps1") -ConfigPath $script:ConfigPath
}

$agentPort = if ($script:Config.agentPort) { [int]$script:Config.agentPort } else { 8090 }
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:$agentPort/")

try {
    $listener.Start()
} catch {
    Write-Error "Failed to start agent on http://+:$agentPort/. Try running PowerShell as Administrator or add a URLACL for this port."
    throw
}

Write-Host "Wallpaper Agent listening on http://localhost:$agentPort/"
Write-Host "Press Ctrl+C to stop."

while ($listener.IsListening) {
    Start-NextQueuedJob
    $context = $listener.GetContext()

    try {
        if ($context.Request.HttpMethod -eq "OPTIONS") {
            Send-Json $context ([ordered]@{ ok = $true }) 200
            continue
        }

        if (-not (Test-Authorized $context)) {
            continue
        }

        $method = $context.Request.HttpMethod
        $path = $context.Request.Url.AbsolutePath.TrimEnd("/")
        if ($path -eq "") { $path = "/" }

        if ($method -eq "GET" -and $path -eq "/api/status") {
            Send-Json $context ([ordered]@{
                ok = $true
                serverVersion = if ($script:Config.serverVersion) { $script:Config.serverVersion } else { "0.1.0-demo" }
                schemaVersion = 1
                features = @($script:Config.features)
                libraryRoot = $script:LibraryRoot
                queueLength = $script:Queue.Count
                runningJobId = $script:RunningJobId
            })
        } elseif ($method -eq "GET" -and ($path -eq "/api/library" -or $path -eq "/library.json")) {
            Send-FileJson $context (Join-Path $script:LibraryRoot "library.json")
        } elseif ($method -eq "GET" -and $path -eq "/api/wallpapers") {
            $manifest = Read-Manifest
            Send-Json $context @($manifest.items)
        } elseif ($method -eq "GET" -and $path -match "^/api/wallpapers/([^/]+)$") {
            $itemId = [uri]::UnescapeDataString($Matches[1])
            Assert-SafeItemId $itemId
            $manifest = Read-Manifest
            $item = @($manifest.items) | Where-Object { $_.id -eq $itemId } | Select-Object -First 1
            if ($item) { Send-Json $context $item } else { Send-Json $context ([ordered]@{ error = "Not found" }) 404 }
        } elseif ($method -eq "POST" -and $path -match "^/api/wallpapers/([^/]+)/unpack$") {
            $itemId = [uri]::UnescapeDataString($Matches[1])
            Assert-SafeItemId $itemId
            $jobId = [guid]::NewGuid().ToString("N")
            Write-JobFile -JobId $jobId -ItemId $itemId -State "pending" -Message "Queued"
            $script:Queue.Enqueue([pscustomobject]@{ jobId = $jobId; itemId = $itemId })
            Start-NextQueuedJob
            Send-Json $context (Read-JobFile $jobId) 202
        } elseif ($method -eq "GET" -and $path -match "^/api/jobs/([^/]+)$") {
            $jobId = [uri]::UnescapeDataString($Matches[1])
            $job = Read-JobFile $jobId
            if ($job) { Send-Json $context $job } else { Send-Json $context ([ordered]@{ error = "Not found" }) 404 }
        } elseif ($method -eq "POST" -and $path -eq "/api/library/rescan") {
            & (Join-Path $PSScriptRoot "Generate-LibraryManifest.ps1") -ConfigPath $script:ConfigPath | Out-Null
            Send-Json $context (Read-Manifest)
        } else {
            Send-Json $context ([ordered]@{ error = "Not found" }) 404
        }
    } catch {
        Send-Json $context ([ordered]@{ error = $_.Exception.Message }) 500
    }
}
