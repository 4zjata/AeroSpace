#!/usr/bin/env bash
set -e

# Navigate to the script's directory
cd "$(dirname "$0")"

echo "=== 1. Building AeroSpace in Release Mode ==="
swift build -c release --product AeroSpaceApp
swift build -c release --product aerospace

echo "=== 2. Stopping running instance ==="
killall AeroSpace 2>/dev/null || true

echo "=== 3. Replacing system binaries ==="
cp .build/x86_64-apple-macosx/release/aerospace /usr/local/bin/aerospace
cp .build/x86_64-apple-macosx/release/AeroSpaceApp /Applications/AeroSpace.app/Contents/MacOS/AeroSpace

echo "=== 4. Re-signing App Bundle ==="
codesign --force --deep --sign - /Applications/AeroSpace.app

echo "=== 5. Launching AeroSpace ==="
open -a AeroSpace

echo "============================================="
echo "Installation complete!"
echo "NOTE: If AeroSpace does not respond, remember to toggle Accessibility permissions:"
echo "System Settings -> Privacy & Security -> Accessibility"
echo "Remove AeroSpace with '-' and add/enable it again."
echo "============================================="
