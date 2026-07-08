#!/bin/bash
set -e

# Dynamically resolve workspace root folder
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
WORKSPACE_DIR="$( dirname "$SCRIPT_DIR" )"

LOGO_PNG="${WORKSPACE_DIR}/Assets/AppIcon.png"
APP_NAME="Smelt"
BUNDLE_DIR="${WORKSPACE_DIR}/Build/${APP_NAME}.app"

echo "=== Starting Build Process for ${APP_NAME} ==="

# 1. Create temporary iconset and generate resolutions
echo " * Generating AppIcon.icns..."
ICONSET_DIR="${WORKSPACE_DIR}/Build/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

sips -s format png -z 16 16     "$LOGO_PNG" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
sips -s format png -z 32 32     "$LOGO_PNG" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
sips -s format png -z 32 32     "$LOGO_PNG" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
sips -s format png -z 64 64     "$LOGO_PNG" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
sips -s format png -z 128 128   "$LOGO_PNG" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
sips -s format png -z 256 256   "$LOGO_PNG" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
sips -s format png -z 256 256   "$LOGO_PNG" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
sips -s format png -z 512 512   "$LOGO_PNG" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
sips -s format png -z 512 512   "$LOGO_PNG" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
sips -s format png -z 1024 1024 "$LOGO_PNG" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET_DIR" -o "${WORKSPACE_DIR}/Build/AppIcon.icns"
rm -rf "$ICONSET_DIR"

# 2. Create app bundle structure
echo " * Creating application bundle directories..."
rm -rf "$BUNDLE_DIR"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"

# 3. Copy helper binaries and seed files into bundle resources
echo " * Copying decryption toolchain into bundle..."
TOOLCHAIN_DIR="${WORKSPACE_DIR}/Toolchain"
cp "${TOOLCHAIN_DIR}/cia-unix" "${BUNDLE_DIR}/Contents/Resources/cia-unix"
cp "${TOOLCHAIN_DIR}/ctrdecrypt" "${BUNDLE_DIR}/Contents/Resources/ctrdecrypt"
cp "${TOOLCHAIN_DIR}/ctrtool" "${BUNDLE_DIR}/Contents/Resources/ctrtool"
cp "${TOOLCHAIN_DIR}/makerom" "${BUNDLE_DIR}/Contents/Resources/makerom"
cp "${TOOLCHAIN_DIR}/seeddb.bin" "${BUNDLE_DIR}/Contents/Resources/seeddb.bin"

# Make sure all binaries have executable permissions inside the bundle
chmod +x "${BUNDLE_DIR}/Contents/Resources/cia-unix"
chmod +x "${BUNDLE_DIR}/Contents/Resources/ctrdecrypt"
chmod +x "${BUNDLE_DIR}/Contents/Resources/ctrtool"
chmod +x "${BUNDLE_DIR}/Contents/Resources/makerom"

# 4. Copy icons and convert images to proper PNG format in resources
cp "${WORKSPACE_DIR}/Build/AppIcon.icns" "${BUNDLE_DIR}/Contents/Resources/AppIcon.icns"
sips -s format png "$LOGO_PNG" --out "${BUNDLE_DIR}/Contents/Resources/AppIcon.png" >/dev/null
cp "${WORKSPACE_DIR}/Assets/cover.png" "${BUNDLE_DIR}/Contents/Resources/cover.png"
rm -f "${WORKSPACE_DIR}/Build/AppIcon.icns"

# 5. Compile Swift app binary
echo " * Compiling native SwiftUI application..."
swiftc -sdk $(xcrun --show-sdk-path) -parse-as-library "${WORKSPACE_DIR}/Source/Model.swift" "${WORKSPACE_DIR}/Source/Views.swift" -o "${BUNDLE_DIR}/Contents/MacOS/Smelt"

# 6. Write Info.plist
echo " * Generating Info.plist..."
cat << 'EOF' > "${BUNDLE_DIR}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Smelt</string>
    <key>CFBundleIdentifier</key>
    <string>com.smelt.Smelt</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Smelt</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

# 7. Clear macOS security quarantine blocks
echo " * De-quarantining application bundle..."
xattr -d -r com.apple.quarantine "$BUNDLE_DIR" 2>/dev/null || true

# 8. Copy app bundle to user Downloads folder for easy access
echo " * Deploying application copy..."
rm -rf "$HOME/Downloads/${APP_NAME}.app"
cp -R "$BUNDLE_DIR" "$HOME/Downloads/${APP_NAME}.app"
xattr -d -r com.apple.quarantine "$HOME/Downloads/${APP_NAME}.app" 2>/dev/null || true

# 9. Force Launch Services to register and refresh icon cache
echo " * Refreshing system Launch Services registration..."
touch "$HOME/Downloads/${APP_NAME}.app"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$HOME/Downloads/${APP_NAME}.app"

echo "=== Build and Deployment Complete! ==="
echo "App is available at:"
echo "1. ${BUNDLE_DIR}  (Build Output)"
echo "2. $HOME/Downloads/${APP_NAME}.app  (Downloads Directory)"
