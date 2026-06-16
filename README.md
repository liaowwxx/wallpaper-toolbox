# WallPaper Gallery

WallPaper Gallery is a SwiftUI wallpaper toolbox for Wallpaper Engine resources. The main app is a macOS-native browser and manager for local libraries, with RePKG extraction and image/video wallpaper setting support.

This repository also contains early cross-platform demos:

- `Apps/iOSDemo`: an iPhone/iPad client for browsing a remote Windows wallpaper library.
- `Apps/WindowsServerDemo`: a Streamlit-controlled Windows server demo that scans Wallpaper Engine folders, generates thumbnails, serves a manifest, and runs RePKG unpack jobs on demand.
- `docs/cross-platform-windows-server-plan.md`: the design plan for the remote Windows library workflow.

## macOS App

```bash
swift run
```

Build release binary:

```bash
swift build -c release
```

Build app bundle or DMG:

```bash
make app
make dmg
```

The macOS app expects the bundled native video wallpaper player at `resources/bin/WallpaperPlayer` and the bundled RePKG runtime under `resources/osx-arm64`. Set `REPKG_PATH` to override the RePKG executable at runtime.

## Remote Windows Demo

The current remote workflow is API-server first:

1. Run the Streamlit control panel on the Windows PC.
2. Choose the Wallpaper Engine library root, `RePKG.exe`, and optional `ffmpeg.exe`.
3. Set `API username` and `API password` to enable Basic Auth.
4. Generate thumbnails and `library.json`.
5. Start the API server.
6. On iOS, enter the Streamlit-provided API URL plus the same username/password.

For normal iOS use, leave `Public static base URL` blank. The iOS app loads thumbnails and media through the API `/files/...` endpoint. That endpoint only serves files already published in `library.json`, so unrelated files under the library root are not exposed.

`miniserve` is currently optional and localhost-only in the demo. It is useful for local debugging on the Windows PC, but it is not part of the normal iOS workflow.

See `Apps/WindowsServerDemo/README.md` and `Apps/iOSDemo/README.md` for setup details.

## Repository Layout

```text
Sources/                  macOS SwiftUI app
Apps/iOSDemo/             iOS/iPadOS remote client demo
Apps/WindowsServerDemo/   Windows Streamlit + FastAPI server demo
docs/                     cross-platform planning notes
resources/                bundled macOS runtime assets
scripts/                  helper scripts
```
