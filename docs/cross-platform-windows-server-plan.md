# Cross-Platform Windows Server Plan

## Goal

Build a shared wallpaper library experience across macOS, iPadOS, and iOS.

The Windows PC stores Wallpaper Engine resources, runs the native Windows RePKG CLI, and serves unpacked assets over the local network. Apple clients browse, preview, download, export, and optionally trigger remote unpack jobs.

## Product Boundaries

### macOS

- Keep existing local library mode.
- Keep local RePKG extraction.
- Keep macOS wallpaper setting.
- Add remote Windows library mode.
- Allow remote assets to be previewed, downloaded, and optionally cached locally before setting as macOS wallpaper.

### iPadOS / iOS

- No system wallpaper setting feature.
- Browse remote Windows library.
- Preview images and videos.
- Save images/videos to Photos or Files.
- Trigger remote unpacking only through a Windows agent API.

### Windows PC

- Owns raw Wallpaper Engine resources.
- Runs RePKG CLI.
- Generates thumbnails and manifests.
- Serves extracted files through `miniserve`.
- Optionally runs a small Windows agent for API/job control.

## Recommended Architecture

```text
Windows PC
  ├─ Wallpaper resource directory
  ├─ RePKG CLI
  ├─ Manifest / thumbnail generator
  ├─ miniserve static file server
  └─ Optional Windows agent API

Apple clients
  ├─ macOS app
  ├─ iPadOS app
  └─ iOS app
```

## Why Use miniserve

`miniserve` is a good fit as the static file serving layer:

- Single binary.
- Cross-platform, including Windows.
- Serves directories over HTTP.
- Supports authentication.
- Supports TLS if needed.
- Supports Range requests, which is important for video preview with `AVPlayer`.
- Supports QR code display for quick connection.
- Supports WebDAV and uploads, though these are optional.

Do not make the app parse miniserve's HTML directory listings. Generate a stable `library.json` manifest and let clients consume that instead.

## Suggested Windows Directory Layout

```text
D:\WallpaperLibrary
  ├─ packages
  ├─ extracted
  ├─ thumbs
  └─ library.json
```

Example miniserve command:

```powershell
miniserve-win.exe `
  -i 0.0.0.0 `
  -p 8080 `
  --auth user:password `
  --qrcode `
  --no-symlinks `
  D:\WallpaperLibrary
```

## Manifest Shape

First version can be static JSON:

```json
{
  "schemaVersion": 1,
  "serverVersion": "0.1.0",
  "generatedAt": "2026-06-15T00:00:00Z",
  "features": ["rangeStreaming", "staticManifest"],
  "items": [
    {
      "id": "281990",
      "title": "Rainy Street",
      "type": "video",
      "thumbnail": "/thumbs/281990.jpg",
      "isUnpacked": true,
      "tags": ["city", "rain"],
      "collections": ["Favorites"],
      "assets": [
        {
          "id": "281990-main-video",
          "name": "scene.mp4",
          "kind": "video",
          "url": "/extracted/281990/scene.mp4",
          "size": 104857600
        }
      ]
    }
  ]
}
```

## Optional Windows Agent API

Use this only after static browsing works.

```text
GET  /api/status
GET  /api/library
GET  /api/wallpapers
GET  /api/wallpapers/{id}
POST /api/wallpapers/{id}/unpack
GET  /api/jobs/{jobId}
POST /api/library/rescan
```

The Windows agent should:

- Restrict all operations to configured library roots.
- Queue RePKG jobs instead of running unlimited parallel processes.
- Write job states: `pending`, `running`, `done`, `failed`.
- Regenerate `library.json` after successful unpacking.
- Return stable asset IDs and URLs served by miniserve.

## Shared Code Strategy

Create shared modules instead of hard-coding platform checks throughout the app.

```text
Packages/
  WallpaperCore
    Models
    Manifest decoding
    Search/filter/sort
    Library state
    Protocols

  WallpaperRemote
    RemoteLibraryClient
    Auth
    Download and streaming URL handling
    Windows agent API models

  WallpaperSharedUI
    WallpaperGrid
    WallpaperCard
    AssetPreview
    FilterControls

Apps/
  MacApp
    Local RePKG extraction
    macOS wallpaper setting
    Finder/OpenPanel integration
    Remote Windows mode

  iOSApp
    Photos export
    Files export
    iPhone/iPad navigation
    Local network permission flow
```

## Reuse Estimate

| Area | Expected reuse | Notes |
|---|---:|---|
| Models | 80-95% | `WallpaperItem`, `AssetFile`, manifest models, tags, collections |
| Remote API client | 90%+ | Shared HTTP/JSON implementation |
| Search/filter/sort | 80-95% | Platform-neutral |
| Thumbnail/cache pipeline | 60-80% | Keep URL/cache logic shared; image types may need platform wrappers |
| Gallery UI | 60-80% | Shared cards/grid; different shells for macOS/iPad/iPhone |
| Video preview | 60-75% | `AVPlayer` shared; platform view wrappers differ |
| Wallpaper setting | macOS only | iOS/iPadOS can expose save/export instead |
| Local RePKG extraction | macOS/Windows only | iOS/iPadOS should not run CLI extraction locally |

## Protocol Boundaries

Prefer protocols for platform and source differences:

```swift
protocol LibrarySource {
    func loadLibrary() async throws -> [WallpaperItem]
    func assets(for itemID: String) async throws -> [AssetFile]
}

protocol WallpaperUnpacker {
    func unpack(_ itemID: String) async throws -> UnpackJob
}

protocol AssetExporter {
    func save(_ asset: AssetFile) async throws
}
```

Example implementations:

```text
macOS
  LocalLibrarySource
  RemoteWindowsLibrarySource
  LocalRePKGUnpacker
  RemoteWindowsUnpacker
  MacWallpaperApplier

iOS / iPadOS
  RemoteWindowsLibrarySource
  RemoteWindowsUnpacker
  PhotosAssetExporter
  FilesAssetExporter
```

## Platform UI Direction

### macOS

- Keep `NavigationSplitView`.
- Add a source selector: `Local Library` / `Windows Library`.
- Add connection status in sidebar or toolbar.
- Add a Settings pane for Windows server URL, auth, and cache limits.
- For remote videos, stream from miniserve when previewing.
- For setting a remote asset as macOS wallpaper, download to local cache first.

### iPadOS

- Use a three-column layout where available:
  - Sidebar: library, filters, collections.
  - Content: wallpaper grid.
  - Detail: preview, assets, actions.
- Favor direct preview and export actions.

### iOS

- Use a compact navigation stack or tabs:
  - Library
  - Collections
  - Settings
- Detail screen handles preview, save, export, and unpack job status.

## Version Management

Use three related version layers.

### App Version

- macOS and iOS/iPadOS can share marketing versions, for example `1.3.0`.
- Build numbers should be platform-specific and monotonically increasing.

### Manifest / API Version

Always include schema and feature information:

```json
{
  "schemaVersion": 1,
  "serverVersion": "0.2.0",
  "features": ["rangeStreaming", "unpackJobs", "thumbnails"]
}
```

Clients should:

- Refuse unsupported `schemaVersion` values.
- Use `features` to enable/disable UI actions.
- Show clear upgrade messages when server/app versions are incompatible.

### Git Tags

Use separate tags for app and server components:

```text
app-v1.0.0
windows-agent-v0.3.0
schema-v1
```

If the Windows agent lives in the same repository, keep a changelog section per component.

## Implementation Phases

### Phase 1: Static Remote Library MVP

- Windows script scans resources.
- Windows script extracts or indexes already extracted assets.
- Windows script generates thumbnails.
- Windows script writes `library.json`.
- miniserve serves the library directory.
- macOS reads remote `library.json`.
- iPadOS/iOS reads remote `library.json`.
- Clients browse, preview, and save/download assets.

### Phase 2: Shared Core Refactor

- Extract shared models and manifest decoder.
- Extract shared search/filter/sort logic.
- Extract remote client.
- Keep current macOS local features behind platform-specific services.

### Phase 3: Windows Agent

- Add `/api/status`.
- Add `/api/library`.
- Add unpack job endpoints.
- Add library rescan endpoint.
- Add job progress and error reporting.
- Keep miniserve for heavy static file transfer.

### Phase 4: Better Discovery and UX

- Add Bonjour/mDNS discovery if practical.
- Add QR code pairing flow.
- Add cached server profiles.
- Add offline thumbnail cache.
- Add connection diagnostics.
- Add server compatibility screen.

## Main Risks

- iOS local network permission requires clear onboarding.
- HTTP local networking may need App Transport Security configuration.
- Windows Firewall may block miniserve/agent until allowed.
- Large videos need Range request support and stable URLs.
- Remote paths must never expose arbitrary Windows filesystem access.
- iOS/iPadOS should not depend on RePKG CLI or external process execution.

## Recommended Next Step

Build the lowest-risk vertical slice:

1. Create a sample `library.json`.
2. Serve it with miniserve from Windows or a local test directory.
3. Add `RemoteWindowsLibrarySource` to macOS.
4. Display the remote library in the existing gallery.
5. Reuse the same client code in an iPadOS target.

This validates the network model, media preview, and UI reuse before adding a Windows agent or remote unpack jobs.
