#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
DEB_FILE=""
DOWNLOAD_DEB=0
REGION="global"
EXTRACT_DIR="$WORKDIR/extracted"
APPDIR="$WORKDIR/AnycubicSlicer.AppDir"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --deb)
      DEB_FILE="$2"
      shift 2
      ;;
    --download)
      DOWNLOAD_DEB=1
      shift
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--deb /path/to/package.deb] [--download [--region china|global]]"
      echo ""
      echo "Options:"
      echo "  --deb FILE       Path to existing .deb file"
      echo "  --download       Download the latest .deb file from CDN"
      echo "  --region REGION  Specify region for download: 'china' or 'global' (default: global)"
      exit 1
      ;;
  esac
done

# Download deb file if requested
if [ $DOWNLOAD_DEB -eq 1 ]; then
  # Set CDN URL based on region
  if [ "$REGION" = "china" ]; then
    REPO_URL="https://cdn-platform-slicer.anycubicloud.com/prod"
  else
    REPO_URL="https://cdn-universe-slicer.anycubic.com/prod"
  fi
  
  echo "Downloading package list from $REGION region..."
  
  # Get the Packages file to find the latest deb
  PACKAGES_URL="$REPO_URL/dists/noble/main/binary-amd64/Packages"
  PACKAGES_FILE="$WORKDIR/Packages.tmp"
  
  if command -v curl &> /dev/null; then
    curl -L -o "$PACKAGES_FILE" "$PACKAGES_URL" || {
      echo "Error: Failed to download package list"
      exit 1
    }
  elif command -v wget &> /dev/null; then
    wget -O "$PACKAGES_FILE" "$PACKAGES_URL" || {
      echo "Error: Failed to download package list"
      exit 1
    }
  else
    echo "Error: Neither curl nor wget found. Please install one of them."
    exit 1
  fi
  
  # Extract package filename and download URL
  PACKAGE_FILE=$(grep -A 10 "Package: anycubicslicernext" "$PACKAGES_FILE" | grep "Filename:" | head -1 | awk '{print $2}')
  
  if [ -z "$PACKAGE_FILE" ]; then
    echo "Error: Could not find package in repository"
    rm -f "$PACKAGES_FILE"
    exit 1
  fi
  
  PACKAGE_URL="$REPO_URL/$PACKAGE_FILE"
  DEB_FILE="$WORKDIR/$(basename "$PACKAGE_FILE")"
  
  echo "Downloading: $(basename "$PACKAGE_FILE")"
  echo "From: $PACKAGE_URL"
  
  if command -v curl &> /dev/null; then
    curl -L -o "$DEB_FILE" "$PACKAGE_URL" || {
      echo "Error: Failed to download package"
      rm -f "$PACKAGES_FILE"
      exit 1
    }
  else
    wget -O "$DEB_FILE" "$PACKAGE_URL" || {
      echo "Error: Failed to download package"
      rm -f "$PACKAGES_FILE"
      exit 1
    }
  fi
  
  rm -f "$PACKAGES_FILE"
  echo "Download complete: $DEB_FILE"
fi

# Extract from deb file if provided
if [ -n "$DEB_FILE" ]; then
  if [ ! -f "$DEB_FILE" ]; then
    echo "Error: DEB file not found: $DEB_FILE"
    exit 1
  fi
  
  echo "Extracting DEB package: $DEB_FILE"
  rm -rf "$EXTRACT_DIR"
  mkdir -p "$EXTRACT_DIR"
  
  # Extract deb file using dpkg-deb
  dpkg-deb -x "$DEB_FILE" "$EXTRACT_DIR"
  echo "DEB package extracted to: $EXTRACT_DIR"
else
  echo "No DEB file specified. Assuming files are already in: $EXTRACT_DIR"
  if [ ! -d "$EXTRACT_DIR" ]; then
    echo "Error: Extract directory not found: $EXTRACT_DIR"
    echo "Please run with --deb option or ensure files are in $EXTRACT_DIR"
    exit 1
  fi
fi

# Extract version from the build-version.txt file in resources
VERSION_FILE="$EXTRACT_DIR/usr/share/AnycubicSlicerNext/resources/build-version.txt"
if [ -f "$VERSION_FILE" ]; then
  VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
  echo "Detected version from build-version.txt: $VERSION"
else
  VERSION="unknown"
  echo "Warning: Could not find build-version.txt, using version: $VERSION"
fi

echo "Building AppImage in: $WORKDIR"

rm -rf "$APPDIR"
mkdir -p "$APPDIR"

echo "Copying package files into AppDir with flat structure..."
# Copy with flat structure (bin, lib, resources at root like working AppImage)
cp -a "$EXTRACT_DIR/usr/bin" "$APPDIR/"
cp -a "$EXTRACT_DIR/usr/lib" "$APPDIR/"
cp -a "$EXTRACT_DIR/usr/share/AnycubicSlicerNext/resources" "$APPDIR/"

# Look for bundled runtime in common locations (for glibc compatibility with older systems)
REFERENCE_RUNTIME=""
for runtime_path in "$WORKDIR/../squashfs-root/runtime" "$WORKDIR/squashfs-root/runtime" "$EXTRACT_DIR/usr/runtime"; do
  if [ -d "$runtime_path" ]; then
    REFERENCE_RUNTIME="$runtime_path"
    break
  fi
done

if [ -n "$REFERENCE_RUNTIME" ]; then
  echo "Copying bundled runtime from $REFERENCE_RUNTIME for better compatibility..."
  cp -a "$REFERENCE_RUNTIME" "$APPDIR/"
else
  echo "No bundled runtime found, skipping..."
fi

# Also copy the LICENSE if it exists
if [ -f "$EXTRACT_DIR/usr/LICENSE.txt" ]; then
  cp -a "$EXTRACT_DIR/usr/LICENSE.txt" "$APPDIR/"
fi

# Create share directory for desktop integration
mkdir -p "$APPDIR/share/applications" "$APPDIR/share/icons/hicolor/256x256/apps"

echo "Ensuring main binary is executable..."
chmod +x "$APPDIR/bin/AnycubicSlicerNext" || true

ICON_SRC="$APPDIR/resources/images/AnycubicSlicer.png"
ICON_DST="$APPDIR/share/icons/hicolor/256x256/apps/AnycubicSlicer.png"
mkdir -p "$(dirname "$ICON_DST")"
if [ -f "$ICON_SRC" ]; then
  cp -a "$ICON_SRC" "$ICON_DST"
  echo "Copied icon to $ICON_DST"
else
  echo "Warning: icon source not found: $ICON_SRC"
fi

# appimagetool also likes a top-level icon file (AnycubicSlicer.png/.svg)
if [ -f "$ICON_DST" ]; then
  cp -a "$ICON_DST" "$APPDIR/AnycubicSlicer.png"
  echo "Copied top-level icon to $APPDIR/AnycubicSlicer.png"
fi
if [ -f "$APPDIR/resources/images/AnycubicSlicer.svg" ]; then
  cp -a "$APPDIR/resources/images/AnycubicSlicer.svg" "$APPDIR/AnycubicSlicer.svg"
  echo "Copied top-level svg icon to $APPDIR/AnycubicSlicer.svg"
fi

DESKTOP_SRC="$EXTRACT_DIR/usr/share/applications/AnycubicSlicer.desktop"
DESKTOP="$APPDIR/share/applications/AnycubicSlicer.desktop"
if [ -f "$DESKTOP_SRC" ]; then
  cp -a "$DESKTOP_SRC" "$DESKTOP"
  sed -i 's|Icon=.*|Icon=AnycubicSlicer|' "$DESKTOP"
  sed -i 's|Exec=.*|Exec=AnycubicSlicerNext %U|' "$DESKTOP"
  echo "Patched desktop file: $DESKTOP"
else
  echo "Warning: desktop file not found: $DESKTOP_SRC"
fi

# appimagetool expects a .desktop file at AppDir root as well
if [ -f "$DESKTOP" ]; then
  cp -a "$DESKTOP" "$APPDIR/AnycubicSlicer.desktop"
  echo "Copied desktop file to $APPDIR/AnycubicSlicer.desktop"
fi

# Create AppStream metadata for GearLever version detection
echo "Creating AppStream metadata for version detection..."
mkdir -p "$APPDIR/share/metainfo"
APPSTREAM_FILE="$APPDIR/share/metainfo/AnycubicSlicer.appdata.xml"
cat > "$APPSTREAM_FILE" <<APPSTREAM_EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>AnycubicSlicer</id>
  <name>AnycubicSlicer</name>
  <summary>3D Printing Software</summary>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>AGPL-3.0</project_license>
  <developer_name>Anycubic</developer_name>
  <description>
    <p>AnycubicSlicer is a complete 3D printing solution for Anycubic 3D printers.</p>
  </description>
  <launchable type="desktop-id">AnycubicSlicer.desktop</launchable>
  <releases>
    <release version="$VERSION" date="$(date +%Y-%m-%d)"/>
  </releases>
  <categories>
    <category>Graphics</category>
    <category>Engineering</category>
  </categories>
</component>
APPSTREAM_EOF
echo "Created AppStream metadata with version: $VERSION"

# GearLever also looks for metadata at the root of the AppImage
cp "$APPSTREAM_FILE" "$APPDIR/AnycubicSlicer.appdata.xml"
echo "Copied AppStream metadata to AppDir root for GearLever"

echo "Creating AppRun launcher..."
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/bash
DIR=$(readlink -f "$0" | xargs dirname)

# Set library path (include runtime if available for glibc compatibility)
if [ -d "$DIR/runtime" ]; then
  export LD_LIBRARY_PATH="$DIR/runtime:$DIR/lib:$DIR/bin:$LD_LIBRARY_PATH"
else
  export LD_LIBRARY_PATH="$DIR/lib:$DIR/bin:$LD_LIBRARY_PATH"
fi

# FIXME: Slicer segfault workarounds (from OrcaSlicer)
# 1) Slicer will segfault on systems where locale info is not as expected (i.e. Holo-ISO arch-based distro)
export LC_ALL=C

# Wayland/NVIDIA workarounds for graphics rendering
if [ "$XDG_SESSION_TYPE" = "wayland" ] && [ "$ZINK_DISABLE_OVERRIDE" != "1" ]; then
    if command -v glxinfo >/dev/null 2>&1; then
        RENDERER=$(glxinfo | grep "OpenGL renderer string:" | sed 's/.*: //')
        if echo "$RENDERER" | grep -qi "NVIDIA"; then
            if command -v nvidia-smi >/dev/null 2>&1; then
                DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)
                DRIVER_MAJOR=$(echo "$DRIVER_VERSION" | cut -d. -f1)
                [ "$DRIVER_MAJOR" -gt 555 ] && ZINK_FORCE_OVERRIDE=1
            fi
            if [ "$ZINK_FORCE_OVERRIDE" = "1" ]; then
                export __GLX_VENDOR_LIBRARY_NAME=mesa
                export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
                export MESA_LOADER_DRIVER_OVERRIDE=zink
                export GALLIUM_DRIVER=zink
                export WEBKIT_DISABLE_DMABUF_RENDERER=1
            fi
        fi
    fi
fi

# CRITICAL: Set resource path for the application to find fonts and other resources
export ANYCUBIC_RESOURCES_PATH="$DIR/resources"

# WebKit rendering fixes
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_FORCE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1

# Detect Box64 emulation (check for BOX64 env var or if running under box64)
if [ -n "$BOX64_PATH" ] || [ -n "$BOX64_LOG" ] || grep -qi box64 /proc/self/maps 2>/dev/null; then
  # Running under Box64 - do NOT use bundled linker, let Box64 handle it
  # Box64 needs direct execution to properly intercept library loading
  exec "$DIR/bin/AnycubicSlicerNext" "$@"
else
  # Native x86_64 execution - use bundled linker if available
  if [ -f "$DIR/runtime/ld-linux-x86-64.so.2" ]; then
    exec "$DIR/runtime/ld-linux-x86-64.so.2" --library-path "$LD_LIBRARY_PATH" "$DIR/bin/AnycubicSlicerNext" "$@"
  else
    exec "$DIR/bin/AnycubicSlicerNext" "$@"
  fi
fi
EOF
chmod +x "$APPDIR/AppRun"

# Create VERSION file at AppDir root for GearLever
if [ "$VERSION" != "unknown" ]; then
  echo "$VERSION" > "$APPDIR/VERSION"
  echo "Created VERSION file with: $VERSION"
fi

APPIMAGETOOL="$WORKDIR/appimagetool-x86_64.AppImage"
if [ ! -x "$APPIMAGETOOL" ]; then
  echo "Downloading appimagetool..."
  curl -L -o "$APPIMAGETOOL" "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
  chmod +x "$APPIMAGETOOL"
fi

echo "Running appimagetool to build AppImage..."
# Set VERSION environment variable for appimagetool
export VERSION="$VERSION"
"$APPIMAGETOOL" --no-appstream "$APPDIR"

# Rename the AppImage to include version number
if [ "$VERSION" != "unknown" ]; then
  OLD_NAME="AnycubicSlicer-x86_64.AppImage"
  NEW_NAME="AnycubicSlicer-${VERSION}-x86_64.AppImage"
  if [ -f "$WORKDIR/$OLD_NAME" ]; then
    mv "$WORKDIR/$OLD_NAME" "$WORKDIR/$NEW_NAME"
    echo "Renamed to: $NEW_NAME"
  fi
fi

echo "Build finished. Check for .AppImage in: $WORKDIR"
