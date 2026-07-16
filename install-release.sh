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

echo "=== 3a. Installing Scripting Addition ==="
mkdir -p /Applications/AeroSpace.app/Contents/Resources/
clang -dynamiclib -framework Cocoa -framework CoreGraphics -O3 -o /Applications/AeroSpace.app/Contents/Resources/sa_payload.dylib Sources/sa/sa_payload.m
clang -framework Cocoa -O3 -o /usr/local/bin/aerospace-sa-loader Sources/sa/sa_loader.m

echo "=== 3b. Installing Scripting Addition LaunchDaemon Helper ==="
sudo tee /usr/local/bin/aerospace-sa-helper.sh > /dev/null << 'EOF'
#!/bin/bash
echo "$(date): AeroSpace helper started"
last_pid=""
while true; do
    pid=$(pgrep -x Dock)
    if [ -n "$pid" ] && [ "$pid" != "$last_pid" ]; then
        echo "$(date): Dock PID changed to $pid. Injecting payload..."
        /usr/local/bin/aerospace-sa-loader
        last_pid="$pid"
    fi
    sleep 5
done
EOF
sudo chmod +x /usr/local/bin/aerospace-sa-helper.sh

sudo tee /Library/LaunchDaemons/bobko.aerospace.helper.plist > /dev/null << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>bobko.aerospace.helper</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/aerospace-sa-helper.sh</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/aerospace-helper.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/aerospace-helper.log</string>
</dict>
</plist>
EOF

sudo chown root:wheel /Library/LaunchDaemons/bobko.aerospace.helper.plist
sudo chmod 644 /Library/LaunchDaemons/bobko.aerospace.helper.plist

sudo launchctl unload /Library/LaunchDaemons/bobko.aerospace.helper.plist 2>/dev/null || true
sudo launchctl load -w /Library/LaunchDaemons/bobko.aerospace.helper.plist

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
