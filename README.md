# WallPaper Gallery

WallPaper Gallery is a macOS-native SwiftUI toolbox for local Wallpaper Engine libraries. It scans wallpaper folders, generates previews, extracts `.pkg` assets through RePKG, and can set image, video, and scene wallpapers.

The macOS app also supports an optional remote mode for browsing a Windows-hosted Wallpaper Engine library. Remote wallpapers are downloaded as original source folders first, then handled by the same local image/video/scene wallpaper pipeline.

The repository also contains early cross-platform demos:

- `Apps/iOSDemo`: an iPhone/iPad client for browsing a remote Windows wallpaper library.
- `Apps/WindowsServerDemo`: a Streamlit-controlled Windows server demo that scans Wallpaper Engine folders, generates thumbnails, serves a manifest, and runs RePKG unpack jobs on demand.
- `docs/cross-platform-windows-server-plan.md`: the design plan for the remote Windows library workflow.

## macOS App

Run from the repository root:

```bash
swift run
```

Build a release binary:

```bash
swift build -c release
```

Build the `.app` bundle or DMG:

```bash
./scripts/build.sh
./scripts/build.sh dmg
```

The app bundle is written to:

```text
.build/WallPaper Gallery.app
```

Open the generated app bundle when testing remote mode. The bundle Info.plist includes App Transport Security and local-network permissions needed for the Windows demo API.

## Wallpaper Support

### Image and Video

Image wallpapers are applied through `NSWorkspace`.

Video wallpapers use the bundled native helper:

```text
resources/bin/WallpaperPlayer
```

The build script copies this helper into the app bundle as `Contents/Resources/WallpaperPlayer`.

### Scene Wallpapers

Scene wallpapers support two paths from the normal `Set as Wallpaper...` flow:

1. The app first attempts the existing RePKG extraction flow for `scene.pkg`.
2. The asset picker opens.
3. At the top of the picker, `Render Scene Directly` starts realtime scene rendering through `wallpaper-wgpu`.
4. Below that, extracted image/video files are still listed and can be selected like normal wallpapers.

This keeps the old extracted-file workflow available while adding realtime scene rendering.

Scene rendering uses:

```text
resources/bin/wallpaper-wgpu
resources/assets/
resources/dxc
resources/lib/libdxcompiler.dylib
```

The renderer is launched with wallpaper/background flags, per-screen geometry, FPS limiting, optional MetalFX upscaling, bundled assets, and saved user property overrides.

### Scene Properties

Scene wallpapers can define user-adjustable options in `project.json -> general.properties`, similar to Wallpaper Engine. Right-click a scene card and choose `Scene Properties...` to edit supported controls:

- sliders
- toggles
- colors
- combo boxes
- text/file values
- conditional visibility

Overrides are saved under Application Support:

```text
~/Library/Application Support/com.wallpaper.gallery/SceneProperties/
```

When a rendered scene is already active, changing scene properties restarts the scene renderer with updated `--user-properties`.

### Scene Performance Settings

Open Settings -> Wallpaper -> Scene Rendering to configure:

- MetalFX upscaling for scene wallpapers
- render scale, default `70%`
- scene FPS cap, default `60 FPS`

`Save & Reapply` persists the settings and restarts the current scene wallpaper using the new values.

## Bundled Runtime Assets

The macOS app expects these resources to exist before packaging:

```text
resources/osx-arm64/RePKG
resources/osx-arm64/*.dll
resources/osx-arm64/*.json
resources/osx-arm64/*.dylib
resources/osx-arm64/*.pdb
resources/bin/WallpaperPlayer
resources/bin/wallpaper-wgpu
resources/assets/
resources/dxc
resources/lib/libdxcompiler.dylib
```

`scripts/build.sh` copies these into the app bundle. `REPKG_PATH`, `WALLPAPER_WGPU_PATH`, and `WALLPAPER_WGPU_ASSETS_PATH` can override the bundled defaults during development.

## Remote Windows Demo

The current remote workflow is API-server first:

1. Run the Streamlit control panel on the Windows PC.
2. Choose the Wallpaper Engine library root, `RePKG.exe`, and optional `ffmpeg.exe`.
3. Set `API username` and `API password` to enable Basic Auth.
4. Generate thumbnails and `library.json`.
5. Start the API server.
6. On macOS or iOS, enter the Streamlit-provided API URL plus the same username/password.

### macOS Remote Mode

Open Settings -> General -> Library, then switch from `Local` to `Remote`.

Remote mode settings:

- `Server URL`: the Windows demo API URL, for example `http://192.168.1.20:8090`.
- `Username` / `Password`: the Basic Auth credentials configured in the Windows control panel.
- Remote download directory: where original wallpaper folders are stored on the Mac.
- `Connect`: fetches the remote `library.json` and shows the remote library.

The app remembers the last selected library mode. If the previous mode was `Remote`, the app automatically attempts to connect on launch. If remote mode is selected but not connected, the gallery stays empty instead of showing the previous local directory.

Each remote wallpaper card is marked as downloaded or not downloaded:

- Not downloaded: the context menu only contains `Download`.
- Downloaded: the context menu is the same as local mode, including `Set as Wallpaper...`, `Set on All Screens...`, scene properties, extraction, Finder, and metadata actions.

Downloads are shown with an in-app progress panel. macOS does not provide a generic native download HUD for custom app transfers, so the app uses a SwiftUI floating progress panel.

### Remote Downloads

Remote macOS downloads do not unpack on Windows. The Windows demo publishes a source archive URL for each wallpaper:

```text
/api/wallpapers/{item_id}/download
```

The endpoint zips the original wallpaper source folder and streams it to the Mac. After download, the app unzips that folder into the configured remote download directory and writes a small registry file:

```text
.wallpaper-remote-downloads.json
```

That registry maps remote item IDs to the downloaded local folder names, so downloaded status can be restored immediately and across app launches. Once downloaded, image, video, and scene wallpapers use the same local setting logic as normal local wallpapers. Scene wallpapers still use the normal scene pipeline: attempt RePKG extraction first, then offer `Render Scene Directly` plus extracted media assets.

The Windows manifest includes:

- `relativeDir`: the source folder's relative location in the Windows library.
- `sourceArchive`: the API route used by the macOS app to download the original folder.
- `thumbnail`: the published thumbnail URL.
- `assets`: published media assets for clients that use the iOS-style streaming flow.

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
