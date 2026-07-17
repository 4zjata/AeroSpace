#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.0.0-SNAPSHOT"
codesign_identity="aerospace-codesign-certificate"
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

#############
### BUILD ###
#############

./build-docs.sh --release
./build-shell-completion.sh

./generate.sh
./script/check-uncommitted-files.sh
./generate.sh --build-version "$build_version" --codesign-identity "$codesign_identity" --generate-git-hash

swift build -c release --arch arm64 --arch x86_64 --product aerospace -Xswiftc -warnings-as-errors # CLI

# todo: make xcodebuild use the same toolchain as swift
# toolchain="$(plutil -extract CFBundleIdentifier raw ~/Library/Developer/Toolchains/swift-6.1-RELEASE.xctoolchain/Info.plist)"
# xcodebuild -toolchain "$toolchain" \
# Unfortunately, Xcode 16 fails with:
#     2025-05-05 15:51:15.618 xcodebuild[4633:13690815] Writing error result bundle to /var/folders/s1/17k6s3xd7nb5mv42nx0sd0800000gn/T/ResultBundle_2025-05-05_15-51-0015.xcresult
#     xcodebuild: error: Could not resolve package dependencies:
#       <unknown>:0: warning: legacy driver is now deprecated; consider avoiding specifying '-disallow-use-new-driver'
#     <unknown>:0: error: unable to execute command: <unknown>

rm -rf .release && mkdir .release

xcode_configuration="Release"
xcodebuild -version
xcodebuild-pretty .release/xcodebuild.log clean build \
    -scheme AeroSpace \
    -destination "generic/platform=macOS" \
    -configuration "$xcode_configuration" \
    -derivedDataPath .xcode-build

git checkout .

cp -r ".xcode-build/Build/Products/$xcode_configuration/AeroSpace.app" .release
cp -r .build/apple/Products/Release/aerospace .release

################
### SIGN CLI ###
################

codesign -s "$codesign_identity" .release/aerospace

################
### VALIDATE ###
################

expected_layout=$(cat <<EOF
.release/AeroSpace.app
.release/AeroSpace.app/Contents
.release/AeroSpace.app/Contents/_CodeSignature
.release/AeroSpace.app/Contents/_CodeSignature/CodeResources
.release/AeroSpace.app/Contents/MacOS
.release/AeroSpace.app/Contents/MacOS/AeroSpace
.release/AeroSpace.app/Contents/Resources
.release/AeroSpace.app/Contents/Resources/default-config.toml
.release/AeroSpace.app/Contents/Resources/AppIcon.icns
.release/AeroSpace.app/Contents/Resources/Assets.car
.release/AeroSpace.app/Contents/Info.plist
.release/AeroSpace.app/Contents/PkgInfo
EOF
)

if test "$expected_layout" != "$(find .release/AeroSpace.app)"; then
    echo "!!! Expect/Actual layout don't match !!!"
    find .release/AeroSpace.app
    exit 1
fi

check-universal-binary() {
    if ! file "$1" | grep --fixed-string -q "Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64"; then
        echo "$1 is not a universal binary"
        exit 1
    fi
}

check-contains-hash() {
    hash=$(git rev-parse HEAD)
    if ! strings "$1" | grep --fixed-string "$hash" > /dev/null; then
        echo "$1 doesn't contain $hash"
        exit 1
    fi
}

check-universal-binary .release/AeroSpace.app/Contents/MacOS/AeroSpace
check-universal-binary .release/aerospace

check-contains-hash .release/AeroSpace.app/Contents/MacOS/AeroSpace
check-contains-hash .release/aerospace

codesign -v .release/AeroSpace.app
codesign -v .release/aerospace

##########################
### SCRIPTING ADDITION ###
##########################

echo "=== Building Universal Scripting Addition ==="
clang -dynamiclib -framework Cocoa -framework CoreGraphics -arch arm64 -arch x86_64 -O3 -o .release/sa_payload.dylib Sources/sa/sa_payload.m
clang -framework Cocoa -arch arm64 -arch x86_64 -O3 -o .release/aerospace-sa-loader Sources/sa/sa_loader.m

codesign -s "$codesign_identity" .release/sa_payload.dylib
codesign -s "$codesign_identity" .release/aerospace-sa-loader

############
### PACK ###
############

# Build standard release
mkdir -p ".release/AeroSpace-v$build_version/manpage" && cp .man/*.1 ".release/AeroSpace-v$build_version/manpage"
cp -r ./legal ".release/AeroSpace-v$build_version/legal"
cp -r .shell-completion ".release/AeroSpace-v$build_version/shell-completion"
cd .release
    mkdir -p "AeroSpace-v$build_version/bin" && cp -r aerospace "AeroSpace-v$build_version/bin"
    cp -r AeroSpace.app "AeroSpace-v$build_version"
    zip -r "AeroSpace-v$build_version.zip" "AeroSpace-v$build_version"
cd -

# Build SIP-Enabled release (packaged with install.sh)
mkdir -p ".release/AeroSpace-v${build_version}-SIP-Enabled"
cp -r ".release/AeroSpace-v${build_version}/manpage" ".release/AeroSpace-v${build_version}-SIP-Enabled/" || true
cp -r ./legal ".release/AeroSpace-v${build_version}-SIP-Enabled/"
cp -r .shell-completion ".release/AeroSpace-v${build_version}-SIP-Enabled/"
mkdir -p ".release/AeroSpace-v${build_version}-SIP-Enabled/bin"
cp .release/aerospace ".release/AeroSpace-v${build_version}-SIP-Enabled/bin/"
cp -r .release/AeroSpace.app ".release/AeroSpace-v${build_version}-SIP-Enabled/"

cat > ".release/AeroSpace-v${build_version}-SIP-Enabled/install.sh" << 'EOF'
#!/bin/bash
set -e
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (using sudo): sudo ./install.sh"
  exit 1
fi
echo "=== 1. Stopping running instance ==="
killall AeroSpace 2>/dev/null || true
echo "=== 2. Installing AeroSpace.app ==="
rm -rf /Applications/AeroSpace.app
cp -r AeroSpace.app /Applications/
echo "=== 3. Installing aerospace CLI ==="
mkdir -p /usr/local/bin
cp bin/aerospace /usr/local/bin/aerospace
echo "=== 4. Re-signing App Bundle ==="
codesign --force --deep --sign - /Applications/AeroSpace.app
echo "=== 5. Launching AeroSpace ==="
if [ -n "$SUDO_USER" ]; then
  sudo -u "$SUDO_USER" open -a AeroSpace
else
  open -a AeroSpace
fi
echo "Installation complete!"
EOF
chmod +x ".release/AeroSpace-v${build_version}-SIP-Enabled/install.sh"

# Build SIP-Disabled release (packaged with embedded SA binaries and install.sh)
mkdir -p ".release/AeroSpace-v${build_version}-SIP-Disabled"
cp -r ".release/AeroSpace-v${build_version}/manpage" ".release/AeroSpace-v${build_version}-SIP-Disabled/" || true
cp -r ./legal ".release/AeroSpace-v${build_version}-SIP-Disabled/"
cp -r .shell-completion ".release/AeroSpace-v${build_version}-SIP-Disabled/"
mkdir -p ".release/AeroSpace-v${build_version}-SIP-Disabled/bin"
cp .release/aerospace ".release/AeroSpace-v${build_version}-SIP-Disabled/bin/"
cp -r .release/AeroSpace.app ".release/AeroSpace-v${build_version}-SIP-Disabled/"

# Copy scripting addition binaries into resources for SIP-Disabled package
cp .release/sa_payload.dylib ".release/AeroSpace-v${build_version}-SIP-Disabled/AeroSpace.app/Contents/Resources/"
cp .release/aerospace-sa-loader ".release/AeroSpace-v${build_version}-SIP-Disabled/AeroSpace.app/Contents/Resources/"
# Re-sign the app bundle
codesign --force --deep --sign "$codesign_identity" ".release/AeroSpace-v${build_version}-SIP-Disabled/AeroSpace.app"

cat > ".release/AeroSpace-v${build_version}-SIP-Disabled/install.sh" << 'EOF'
#!/bin/bash
set -e
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (using sudo): sudo ./install.sh"
  exit 1
fi
echo "=== 1. Stopping running instance ==="
killall AeroSpace 2>/dev/null || true
echo "=== 2. Installing AeroSpace.app ==="
rm -rf /Applications/AeroSpace.app
cp -r AeroSpace.app /Applications/
echo "=== 3. Installing aerospace CLI ==="
mkdir -p /usr/local/bin
cp bin/aerospace /usr/local/bin/aerospace
echo "=== 4. Installing Scripting Addition ==="
cp /Applications/AeroSpace.app/Contents/Resources/aerospace-sa-loader /usr/local/bin/aerospace-sa-loader
chmod +x /usr/local/bin/aerospace-sa-loader
echo "=== 5. Installing LaunchDaemon Helper ==="
tee /usr/local/bin/aerospace-sa-helper.sh > /dev/null << 'INNER_EOF'
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
INNER_EOF
chown root:wheel /usr/local/bin/aerospace-sa-helper.sh
chmod 755 /usr/local/bin/aerospace-sa-helper.sh
tee /Library/LaunchDaemons/bobko.aerospace.helper.plist > /dev/null << 'INNER_EOF'
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
INNER_EOF
chown root:wheel /Library/LaunchDaemons/bobko.aerospace.helper.plist
chmod 644 /Library/LaunchDaemons/bobko.aerospace.helper.plist
launchctl unload /Library/LaunchDaemons/bobko.aerospace.helper.plist 2>/dev/null || true
launchctl load -w /Library/LaunchDaemons/bobko.aerospace.helper.plist
touch /var/log/aerospace-helper.log
chown root:wheel /var/log/aerospace-helper.log
chmod 640 /var/log/aerospace-helper.log
echo "=== 6. Re-signing App Bundle ==="
codesign --force --deep --sign - /Applications/AeroSpace.app
echo "=== 7. Launching AeroSpace ==="
if [ -n "$SUDO_USER" ]; then
  sudo -u "$SUDO_USER" open -a AeroSpace
else
  open -a AeroSpace
fi
echo "Installation complete!"
EOF
chmod +x ".release/AeroSpace-v${build_version}-SIP-Disabled/install.sh"

cd .release
    zip -r "AeroSpace-v${build_version}-SIP-Enabled.zip" "AeroSpace-v${build_version}-SIP-Enabled"
    zip -r "AeroSpace-v${build_version}-SIP-Disabled.zip" "AeroSpace-v${build_version}-SIP-Disabled"
cd -

#################
### Brew Cask ###
#################
for cask_name in aerospace aerospace-dev; do
    ./script/build-brew-cask.sh \
        --cask-name "$cask_name" \
        --zip-uri ".release/AeroSpace-v$build_version.zip" \
        --build-version "$build_version"
done
