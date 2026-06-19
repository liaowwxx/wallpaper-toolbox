# WallPaper Gallery

WallPaper Gallery is a macOS-native SwiftUI toolbox for local Wallpaper Engine libraries. It scans wallpaper folders, generates previews, extracts `.pkg` assets through RePKG, and can set image, video, and scene wallpapers.

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
