# Wallpaper Gallery Windows Server Demo

This demo is the Windows side of the remote-library flow from `docs/cross-platform-windows-server-plan.md`.

It uses two small pieces:

- `miniserve` serves heavy static files: `library.json`, thumbnails, extracted images, and videos.
- `Start-WallpaperAgent.ps1` exposes the optional control API for status, manifest reads, rescans, and queued RePKG unpack jobs.

## Layout

```text
D:\WallpaperLibrary
  packages\
  extracted\
  thumbs\
  jobs\
  logs\
  library.json
```

Put Wallpaper Engine workshop folders or raw `.pkg` files in `packages\`.

Recommended workshop-folder layout:

```text
D:\WallpaperLibrary\packages\281990
  project.json
  preview.jpg
  scene.pkg
```

After unpacking, generated files go to:

```text
D:\WallpaperLibrary\extracted\281990
```

## Dependencies

- RePKG: https://github.com/notscuffed/repkg
- miniserve: https://github.com/svenstaro/miniserve
- Optional `ffmpeg` on `PATH` for video thumbnail generation when no `preview.*` image exists.

The RePKG README documents `extract`, including `-o/--output`, `-c/--copyproject`, and `--overwrite`. The miniserve README documents `--auth`, `-p/--port`, `-i/--interfaces`, `-q/--qrcode`, `-P/--no-symlinks`, and Range request support.

## Quick Start

From PowerShell:

```powershell
cd "...\wallpaper toolbox\Apps\WindowsServerDemo"
Copy-Item .\config.example.json .\config.json
notepad .\config.json
```

Set:

- `libraryRoot`
- `repkgPath`
- `miniservePath`
- `authUser` / `authPassword`

Initialize folders:

```powershell
.\scripts\Initialize-WallpaperLibrary.ps1
```

Generate the first manifest:

```powershell
.\scripts\Generate-LibraryManifest.ps1
```

Start static file serving:

```powershell
.\scripts\Start-MiniServe.ps1
```

Start the optional API agent in a second PowerShell window:

```powershell
.\scripts\Start-WallpaperAgent.ps1
```

If Windows asks about firewall access, allow private-network access for both servers.

## Client URLs

Use these in the iOS demo:

- Library URL: `http://<windows-ip>:8080`
- Agent API URL: `http://<windows-ip>:8090`

If auth is enabled, use the same username and password in the iOS settings.

## API

```text
GET  /api/status
GET  /api/library
GET  /api/wallpapers
GET  /api/wallpapers/{id}
POST /api/wallpapers/{id}/unpack
GET  /api/jobs/{jobId}
POST /api/library/rescan
```

Unpack jobs are queued one at a time in the agent process. Job state files are written to `jobs\`.

## Static Manifest Only

You can skip the agent completely for the Phase 1 browsing flow. Run only:

```powershell
.\scripts\Generate-LibraryManifest.ps1
.\scripts\Start-MiniServe.ps1
```

Then connect the iOS demo to `http://<windows-ip>:8080`.
