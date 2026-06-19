#!/bin/bash
set -euo pipefail

# Build script for creating RePKG ToolBox .app bundle and .dmg
# Prerequisites: Xcode or Xcode Command Line Tools, Swift 5.9+

APP_NAME="WallPaper-Gallery"
BUNDLE_NAME="WallPaper Gallery"
BUNDLE_ID="com.wallpaper.gallery"
VERSION="${VERSION:-1.0.beta}"
BUILD_DIR=".build"
CERT_NAME="${CERT_NAME:-mycert}"
APP_DIR="${BUILD_DIR}/${BUNDLE_NAME}.app"
DMG_NAME="${BUILD_DIR}/WallPaper-Gallery-${VERSION}.dmg"
RESOURCES_DIR="$(cd "$(dirname "$0")/.." && pwd)/resources"
REPKG_BIN="${RESOURCES_DIR}/osx-arm64/RePKG"
REPKG_DLL_DIR="${RESOURCES_DIR}/osx-arm64"
APP_ICON="${RESOURCES_DIR}/AppIcon.icns"

# ---- helpers ----
step()  { echo "==> $1"; }
info()  { echo "    $1"; }
error() { echo "ERROR: $1" >&2; exit 1; }

# ---- build swift binary ----
step "Building Swift release binary"
swift build -c release

BINARY="${BUILD_DIR}/release/${APP_NAME}"
[ -f "$BINARY" ] || BINARY="${BUILD_DIR}/arm64-apple-macosx/release/${APP_NAME}"
[ -f "$BINARY" ] || error "Could not find built binary. Tried release/ and arm64-apple-macosx/release/"
info "Binary: $BINARY"

# ---- construct .app bundle ----
step "Creating app bundle: ${APP_DIR}"
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents"/{MacOS,Resources,Frameworks}

# copy executable
cp "$BINARY" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod 755 "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# copy RePKG CLI + .NET runtime DLLs into bundle
step "Bundling RePKG CLI"
if [ -f "$REPKG_BIN" ]; then
    cp "$REPKG_BIN" "${APP_DIR}/Contents/Resources/RePKG"
    chmod 755 "${APP_DIR}/Contents/Resources/RePKG"

    # copy .NET runtime files so RePKG can run (DLLs, dylibs, config)
    for file in "${REPKG_DLL_DIR}"/*.dll "${REPKG_DLL_DIR}"/*.json \
                "${REPKG_DLL_DIR}"/*.dylib "${REPKG_DLL_DIR}"/*.pdb; do
        [ -f "$file" ] && cp "$file" "${APP_DIR}/Contents/Resources/"
    done
    file_count=$(ls "${REPKG_DLL_DIR}"/*.dll "${REPKG_DLL_DIR}"/*.dylib 2>/dev/null | wc -l)
    info "RePKG + ${file_count} runtime files bundled"
else
    info "RePKG not found at ${REPKG_BIN}, skipping. App will search PATH."
fi

# copy WallpaperPlayer if available
WALLPAPER_PLAYER="${RESOURCES_DIR}/bin/WallpaperPlayer"
if [ -f "$WALLPAPER_PLAYER" ]; then
    cp "$WALLPAPER_PLAYER" "${APP_DIR}/Contents/Resources/WallpaperPlayer"
    chmod 755 "${APP_DIR}/Contents/Resources/WallpaperPlayer"
    info "WallpaperPlayer bundled"
fi

# copy wallpaper-wgpu scene renderer if available
WALLPAPER_WGPU="${RESOURCES_DIR}/bin/wallpaper-wgpu"
if [ -f "$WALLPAPER_WGPU" ]; then
    cp "$WALLPAPER_WGPU" "${APP_DIR}/Contents/Resources/wallpaper-wgpu"
    chmod 755 "${APP_DIR}/Contents/Resources/wallpaper-wgpu"
    info "wallpaper-wgpu bundled"
fi

WALLPAPER_WGPU_ASSETS="${RESOURCES_DIR}/assets"
if [ -d "$WALLPAPER_WGPU_ASSETS" ]; then
    cp -R "$WALLPAPER_WGPU_ASSETS" "${APP_DIR}/Contents/Resources/assets"
    info "wallpaper-wgpu assets bundled"
fi

DXC_BIN="${RESOURCES_DIR}/dxc"
DXC_LIB="${RESOURCES_DIR}/lib/libdxcompiler.dylib"
if [ ! -f "$DXC_BIN" ]; then
    DXC_BIN="${RESOURCES_DIR}/bin/dxc"
fi
if [ ! -f "$DXC_LIB" ]; then
    DXC_LIB="${RESOURCES_DIR}/bin/lib/libdxcompiler.dylib"
fi
if [ -f "$DXC_BIN" ]; then
    cp "$DXC_BIN" "${APP_DIR}/Contents/Resources/dxc"
    chmod 755 "${APP_DIR}/Contents/Resources/dxc"
    info "dxc bundled"
fi
if [ -f "$DXC_LIB" ]; then
    mkdir -p "${APP_DIR}/Contents/Resources/lib"
    cp "$DXC_LIB" "${APP_DIR}/Contents/Resources/lib/libdxcompiler.dylib"
    chmod 755 "${APP_DIR}/Contents/Resources/lib/libdxcompiler.dylib"
    info "libdxcompiler bundled"
fi

if [ -f "$APP_ICON" ]; then
    cp "$APP_ICON" "${APP_DIR}/Contents/Resources/AppIcon.icns"
    info "App icon bundled"
fi

# ---- Info.plist ----
step "Writing Info.plist"
cat > "${APP_DIR}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${BUNDLE_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>${BUNDLE_NAME}</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>MacOSX</string>
	</array>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSSupportsAutomaticTermination</key>
	<true/>
	<key>NSRequiresAquaSystemAppearance</key>
		<false/>
</dict>
</plist>
PLIST

# ---- PkgInfo ----
echo -n 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

# ---- entitlements ----
ENTITLEMENTS="${BUILD_DIR}/entitlements.plist"
cat > "$ENTITLEMENTS" << ENTITLEMENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
	<true/>
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
</dict>
</plist>
ENTITLEMENTS

# ---- code signing ----
step "Code signing with certificate: ${CERT_NAME}"

# verify certificate exists
if security find-identity -v -p codesigning | grep -q "${CERT_NAME}"; then
    # sign bundled binaries first (dylibs, helper tools)
    find "${APP_DIR}/Contents/Resources" -type f \( -name "*.dylib" -o -name "RePKG" -o -name "WallpaperPlayer" -o -name "wallpaper-wgpu" -o -name "dxc" \) | while read -r file; do
        codesign --force --sign "${CERT_NAME}" --timestamp "${file}" 2>/dev/null || true
    done

    # sign main executable
    codesign --force --sign "${CERT_NAME}" --timestamp \
        --entitlements "$ENTITLEMENTS" \
        "${APP_DIR}/Contents/MacOS/${APP_NAME}"

    # sign the .app bundle
    codesign --force --sign "${CERT_NAME}" --timestamp \
        --entitlements "$ENTITLEMENTS" \
        "${APP_DIR}"

    # verify signature
    codesign --verify --verbose "${APP_DIR}" 2>/dev/null && \
        info "Signed: $(codesign -d -vv "${APP_DIR}" 2>&1 | grep 'Authority' | head -1)" || \
        info "Signing completed (verify manually if needed)"
else
    info "Certificate '${CERT_NAME}' not found, falling back to ad-hoc"
    codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || true
fi

# ---- success ----
step "App bundle created at ${APP_DIR}"
echo ""
echo "  open '${APP_DIR}'                          # launch directly"
echo "  $(dirname "$0")/$(basename "$0") dmg       # create DMG"

# ---- dmg (optional argument) ----
if [ "${1:-}" = "dmg" ]; then
    step "Creating DMG: ${DMG_NAME}"
    TMP_DMG="${BUILD_DIR}/tmp.dmg"

    rm -f "$DMG_NAME" "$TMP_DMG"

    hdiutil create -volname "${BUNDLE_NAME}" \
        -srcfolder "${APP_DIR}" \
        -ov -format UDRW \
        "$TMP_DMG" >/dev/null

    # mount & find volume path
    MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG")
    VOL_PATH=$(echo "$MOUNT_OUTPUT" | grep -o '/Volumes/.*' | head -1)
    DEVICE=$(echo "$MOUNT_OUTPUT" | grep '/dev/disk' | head -1 | awk '{print $1}')
    info "Mounted at ${VOL_PATH} (${DEVICE})"

    # create Applications symlink for drag-to-install
    ln -sf /Applications "${VOL_PATH}/Applications" 2>/dev/null || true

    # detach using device
    hdiutil detach "$DEVICE" -quiet 2>/dev/null || \
        hdiutil detach -force "$DEVICE" 2>/dev/null || true
    sleep 0.5

    # convert to compressed read-only DMG
    hdiutil convert "$TMP_DMG" -format UDZO \
        -imagekey zlib-level=9 -o "$DMG_NAME" >/dev/null
    rm -f "$TMP_DMG"

    # sign the DMG
    if security find-identity -v -p codesigning | grep -q "${CERT_NAME}"; then
        codesign --force --sign "${CERT_NAME}" --timestamp "$DMG_NAME"
        info "DMG signed with ${CERT_NAME}"
    else
        codesign --force --sign - "$DMG_NAME" 2>/dev/null || true
        info "DMG ad-hoc signed"
    fi

    step "DMG created at ${DMG_NAME}"
    echo "  open '$(dirname "$DMG_NAME")'              # view in Finder"
fi
