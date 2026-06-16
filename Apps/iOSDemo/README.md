# Wallpaper Gallery iOS Demo

This is a first-pass iOS/iPadOS demo for the Phase 1 remote Windows library flow in `docs/cross-platform-windows-server-plan.md`.

## What It Covers

- Loads a static `library.json` manifest from a Windows/miniserve root.
- Supports Basic Auth for miniserve.
- Browses wallpapers with search, collections, tags, unpacked state, and type badges.
- Previews image thumbnails and streams video assets through `AVPlayer` when the server supports Range requests.
- Exposes iOS-appropriate actions: `ShareLink` export and Save to Photos.
- Includes a remote unpack trigger that calls `POST /api/wallpapers/{id}/unpack` when the manifest advertises `unpackJobs`.

## Run

Open `WallpaperGalleryiOSDemo.xcodeproj` in Xcode and run the `WallpaperGalleryiOSDemo` scheme on an iPhone or iPad simulator.

The app starts with the bundled sample manifest. To connect to a real Windows library from outside the local Wi-Fi, use Tailscale on both the Windows PC and iPhone, then connect to the Windows demo API URL shown by the Streamlit control panel.

Example:

```powershell
miniserve-win.exe `
  -i 0.0.0.0 `
  -p 8080 `
  --auth user:password `
  --qrcode `
  --no-symlinks `
  D:\WallpaperLibrary
```

Then enter a URL like `http://100.x.y.z:8090` in the app settings.

## Current Limits

- This demo does not set the iOS system wallpaper, matching the plan boundary.
- The bundled sample manifest uses relative asset URLs, so previews become real once pointed at a server with matching files.
- `xcodebuild` could not be run in this environment because only Command Line Tools are selected, not a full Xcode developer directory.
