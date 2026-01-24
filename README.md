# AnycubicSlicer AppImage Build Script

This script builds an AppImage package for AnycubicSlicerNext from the Debian package provided by Anycubic.

## Prerequisites

- Linux system (Ubuntu/Debian recommended)
- `dpkg-deb` (usually pre-installed on Debian-based systems)
- Either `curl` or `wget` (for downloading packages)
- Internet connection (if using `--download` option)

## Usage

### Option 1: Download and Build (Recommended)

Download the latest .deb package from the official CDN and build the AppImage:

```bash
./build-appimage.sh --download
```

Download from China CDN:

```bash
./build-appimage.sh --download --region china
```

### Option 2: Build from Local .deb File

If you already have a .deb file:

```bash
./build-appimage.sh --deb /path/to/anycubicslicernext_VERSION_amd64.deb
```

### Option 3: Build from Pre-extracted Files

If you've already extracted the .deb contents to the `extracted` directory:

```bash
./build-appimage.sh
```

## Command Line Options

| Option | Description |
|--------|-------------|
| `--download` | Download the latest .deb package from the CDN before building |
| `--region <china\|global>` | Specify which CDN to download from (default: global) |
| `--deb <path>` | Use a specific .deb file for building |

## Examples

```bash
# Download from global CDN and build
./build-appimage.sh --download

# Download from China mirror and build
./build-appimage.sh --download --region china

# Build from a specific .deb file
./build-appimage.sh --deb ../anycubicslicernext_1.3.995_amd64.deb

# Build from pre-extracted files in ./extracted/
./build-appimage.sh
```

## Output

The script will create an AppImage file in the current directory:
- `AnycubicSlicer-<VERSION>-x86_64.AppImage` (if version is detected)
- `AnycubicSlicer-x86_64.AppImage` (if version cannot be determined)

## What the Script Does

1. **Downloads/Locates Package**: Either downloads the .deb from CDN or uses a provided file
2. **Extracts**: Extracts the .deb package contents to `./extracted/`
3. **Prepares AppDir**: Creates the AppImage directory structure in `./AnycubicSlicer.AppDir/`
4. **Copies Runtime**: Includes bundled runtime for better system compatibility (if available)
5. **Creates AppRun**: Generates the launcher script with necessary environment variables
6. **Builds AppImage**: Uses appimagetool to create the final AppImage
7. **Versions**: Renames the output file with the version number

## Troubleshooting

### "Neither curl nor wget found"
Install either curl or wget:
```bash
sudo apt install curl
# or
sudo apt install wget
```

### "Error: Extract directory not found"
If not using `--deb` or `--download`, make sure files are already extracted to `./extracted/usr/`

### appimagetool Download
The script will automatically download `appimagetool-x86_64.AppImage` on first run if not present.

## CDN Sources

- **Global**: `https://cdn-universe-slicer.anycubic.com/prod`
- **China**: `https://cdn-platform-slicer.anycubicloud.com/prod`

## Notes

- The script preserves the extracted files in `./extracted/` for reuse
- You can manually place files in `./extracted/usr/` if needed
- The script looks for optional runtime libraries in multiple locations for better compatibility
