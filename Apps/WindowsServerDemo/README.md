# Wallpaper Gallery Windows Server Demo

This is the Windows-side demo for the remote library workflow described in `docs/cross-platform-windows-server-plan.md`.

It provides:

- A Streamlit control panel for configuration and service startup.
- Thumbnail and `library.json` generation.
- A small FastAPI API used by the iOS demo.
- Optional miniserve startup for static file serving.
- RePKG unpacking on demand with the same default behavior used by the macOS wallpaper pipeline: `extract -o <output> -s --overwrite <pkg>`.

## Expected Directory

```text
D:\WallpaperLibrary
  |-- 281990
  |   |-- project.json
  |   |-- preview.jpg
  |   `-- scene.pkg
  |-- 843221
  |   |-- project.json
  |   `-- scene.mp4
  |-- extracted
  |-- thumbs
  `-- library.json
```

The demo scans direct child folders. It reads `project.json` for `title`, `type`, `file`, `preview_tagger`, and `repkgcollection` when present.

## Install

```powershell
cd Apps\WindowsServerDemo
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Install or place these binaries somewhere on `PATH`:

- RePKG: <https://github.com/notscuffed/repkg>
- miniserve: <https://github.com/svenstaro/miniserve>
- ffmpeg, optional but recommended for video thumbnails

## Run

```powershell
streamlit run wallpaper_server_demo\streamlit_app.py
```

In the Streamlit page:

1. Set the library root.
2. Set `RePKG.exe`, `miniserve.exe`, and `ffmpeg.exe` paths if they are not on `PATH`.
3. Click `Generate thumbnails + manifest`.
4. Click `Start API server`.
5. Optional: click `Start miniserve` and set `Public static base URL` to the miniserve address, for example `http://192.168.1.20:8080`.

Use the `iOS Settings URL` shown in Streamlit as the iOS app server URL.

## iOS Workflow

- Initial load reads `library.json` and shows title, type, and thumbnail.
- Video wallpapers expose direct video assets and stream from the Windows server.
- Package wallpapers initially expose no media assets.
- When iOS opens a package wallpaper detail screen, it calls `POST /api/wallpapers/{id}/unpack`.
- The Windows server runs RePKG, regenerates `library.json`, and iOS reloads the manifest.
- iOS previews remote files by URL. Files are only downloaded when the user taps Save or Export.

## API

```text
GET  /api/status
GET  /library.json
GET  /api/library
GET  /api/wallpapers
GET  /api/wallpapers/{id}
POST /api/wallpapers/{id}/unpack
GET  /api/jobs/{jobId}
POST /api/library/rescan
GET  /files/{relative_path}
```
