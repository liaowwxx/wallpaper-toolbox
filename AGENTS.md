# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

WallPaper Gallery is a macOS-native SwiftUI app for browsing, managing, and extracting Wallpaper Engine wallpapers on macOS. It wraps the [RePKG](https://github.com/notscuffed/repkg) CLI (.NET) to extract `.pkg` files, manages metadata (ratings, collections, tags), and sets video/image wallpapers via a bundled native player.

| | |
|---|---|
| Package name | `WallPaper-Gallery` |
| Bundle name | `WallPaper Gallery` |
| Target OS | macOS 26+ |
| Language mode | Swift 5 (tools version 6.2) |
| Build system | Swift Package Manager |

## Commands

```bash
# Build release binary
swift build -c release

# Run directly (from repo root, using Package.swift in this directory)
swift run

# Run from parent directory (alternate method from Makefile)
cd .. && swift run --package-path "wallpaper toolbox"

# Build .app bundle
make app

# Build .dmg installer
make dmg

# Clean build artifacts
make clean

# Open in Xcode
open -a Xcode "wallpaper toolbox"
```

The app requires a bundled native video wallpaper player (`resources/bin/WallpaperPlayer`) and the RePKG .NET runtime (`resources/osx-arm64/RePKG` + DLLs). Set the `REPKG_PATH` env var to override the RePKG binary location at runtime.

## Architecture

**MVVM with `@Observable`** — a single `AppViewModel` (marked `@Observable`, `@MainActor`) serves as the central state owner, injected via `.environment()`. All views read/write state through it.

### Directory Layout

```
Sources/
├── App.swift                  # @main entry point, NSApplicationDelegate, WindowGroup
├── Models/
│   ├── WallpaperItem.swift    # WallpaperItem + ProjectJSON + AssetFile + AssetScanner
│   └── AssetFile.swift        # AssetFile model
├── ViewModels/
│   └── AppViewModel.swift     # All app state and logic (~670 lines)
├── Views/
│   ├── ContentView.swift      # NavigationSplitView shell, sidebar sections, batch bar
│   ├── GalleryView.swift      # LazyVGrid of WallpaperCard items with equatable diffing
│   ├── ExtractSheet.swift     # Extraction UI with options/log output
│   ├── AssetPickerSheet.swift # Asset selection for setting wallpapers (video preview, frame capture)
│   └── NewCollectionSheet.swift
├── Services/
│   ├── WallpaperScanner.swift # Directory scanning (subdir/flat modes), thumbnail generation
│   ├── RePKGService.swift     # Process wrapper for RePKG CLI (streaming + awaitable)
│   ├── WallpaperService.swift # Sets macOS desktop wallpaper (image/video), frame capture
│   └── MetadataService.swift  # Read/write project.json and _repkg_meta.json
└── Utils/
    ├── DesignSystem.swift     # Glass effect, shadow view modifiers (.toolbarGlass(), .cardShadow())
    └── ThumbnailCache.swift   # NSCache-backed thumbnail cache + ThumbnailView + preload
```

### Key Design Patterns

- **Two scan modes**: `ScanMode.subdir` scans for Wallpaper Engine workshop directories (expects `project.json` + `preview.*` or `*.pkg` per subdir). `ScanMode.flat` scans recursively for raw image/video files, using `_repkg_meta.json` for metadata persistence.
- **Metadata persistence**: Subdir mode reads/writes `project.json` (adding `contentrating`/`repkgcollection`/`preview_tagger` keys). Flat mode uses a single `_repkg_meta.json` file at the root directory.
- **Wallpaper pipeline**: `startWallpaperPipeline()` extracts the `.pkg` to a cache dir (if needed), scans for media assets with `AssetScanner`, presents `AssetPickerSheet`, then calls `WallpaperService.setWallpaper()`. Video wallpapers use the bundled `WallpaperPlayer` binary.
- **Thumbnail generation**: Two-tier — tries AVAssetImageGenerator for supported video formats, falls back to `ffmpeg` (from Homebrew). 256×256 square-cropped JPEGs written to a `temp_thumb/` directory. `ThumbnailView` lazy-loads from an 800-item NSCache.
- **Equatable view diffing**: `WallpaperCard` conforms to `Equatable` (compares only `item.id` + `isSelected`) wrapping a stateful `WallpaperCardInternal` that handles hover/context menu — prevents unnecessary SwiftUI body re-evaluations.
- **RePKG process management**: `RePKGService.run()` is fire-and-forget with streaming callbacks; `runAndWait()` is a structured concurrency variant using `withCheckedThrowingContinuation`. The bundled `RePKG` executable is resolved from `REPKG_PATH` env var → bundle resources → `$PATH`.
- **State persistence**: `UserDefaults` saves selected directory, output directory, scan mode, wallpaper preferences. Last-set wallpaper path is stored separately for restore-on-launch.

### Dependencies

- `AVFoundation` / `AVKit` — video thumbnail generation and in-app video preview
- `AppKit` — `NSOpenPanel`, `NSWorkspace.setDesktopImageURL`, `NSScreen`
- `CGImage` / `ImageIO` — thumbnail processing (crop, resize, JPEG encode)
- External: RePKG .NET CLI (bundled), `ffmpeg` (optional, for video thumbnail fallback)
