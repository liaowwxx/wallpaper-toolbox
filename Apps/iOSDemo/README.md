# Wallpaper Gallery iOS Demo

This is a first-pass iOS/iPadOS demo for the Phase 1 remote Windows library flow in `docs/cross-platform-windows-server-plan.md`.

## What It Covers

- Loads `library.json` from the Windows API server.
- Supports API Basic Auth for manifest, unpack, thumbnails, video preview, and save-to-Photos downloads.
- Browses wallpapers with search, collections, tags, unpacked state, and type badges.
- Previews image thumbnails and streams video assets through `AVPlayer` when the server supports Range requests.
- Exposes iOS-appropriate actions: `ShareLink` export and Save to Photos.
- Includes a remote unpack trigger that calls `POST /api/wallpapers/{id}/unpack` when the manifest advertises `unpackJobs`.

## Run

Open `WallpaperGalleryiOSDemo.xcodeproj` in Xcode and run the `WallpaperGalleryiOSDemo` scheme on an iPhone or iPad simulator.

The app starts with the bundled sample manifest. To connect to a real Windows library:

1. Start the Windows server demo from `Apps\WindowsServerDemo`.
2. In Streamlit, set `API username` and `API password` if you want Basic Auth.
3. Generate thumbnails and `library.json`.
4. Start the API server.
5. Copy the `iOS Settings URL` shown in Streamlit.
6. In the iOS app Settings tab, enter the server URL and the same API username/password.

Tailscale is the recommended remote-access path when the iPhone is not on the same local network as the Windows PC. Join both devices to the same tailnet and use the Tailscale URL shown by the Windows Streamlit page, usually `http://100.x.y.z:8090`.

For the normal workflow, keep the Windows demo's `Public static base URL` blank. The iOS app will use the API server's `/files/...` endpoint for thumbnails and media files.

## Current Limits

- This demo does not set the iOS system wallpaper, matching the plan boundary.
- The bundled sample manifest uses relative asset URLs, so previews become real once pointed at a server with matching files.
- `ShareLink` exports the remote URL. Save to Photos downloads the selected media file and does not keep it locally after the save operation completes.
