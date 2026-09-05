#!/usr/bin/env bash
set -e

echo ""
echo "🎙️  Installing SuperWhisper for macOS..."
echo ""

# 1. Check OS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ Error: SuperWhisper is built specifically for macOS."
    exit 1
fi

MACOS_VERSION=$(sw_vers -productVersion | cut -d. -f1)
if [[ "$MACOS_VERSION" -lt 14 ]]; then
    echo "⚠️ Warning: SuperWhisper is optimized for macOS 14.0 (Sonoma) or newer. Current: $(sw_vers -productVersion)"
fi

# 2. Check Xcode Command Line Tools / Swift
if ! command -v swift &> /dev/null; then
    echo "❌ Error: Swift compiler not found."
    echo "   Please install Xcode Command Line Tools by running: xcode-select --install"
    exit 1
fi

# 3. Determine if running inside existing repo or remote via curl
ORIGINAL_DIR="$(pwd)"
if [[ -f "Package.swift" && -d "Sources/SuperWhisper" ]]; then
    WORKDIR="$(pwd)"
    IS_LOCAL=true
else
    WORKDIR=$(mktemp -d -t superwhisper_install_XXXXXX)
    IS_LOCAL=false
    echo "📦 Downloading latest SuperWhisper source..."
    git clone --depth 1 https://github.com/1nickzakharov-glitch/SuperWhisper.git "$WORKDIR"
    cd "$WORKDIR"
fi

echo "⚙️  Compiling SuperWhisper (Release mode)..."
swift build -c release

echo "📦 Assembling application bundle..."
mkdir -p SuperWhisper.app/Contents/MacOS
cp .build/release/SuperWhisper SuperWhisper.app/Contents/MacOS/SuperWhisper

echo "🔏 Code-signing application..."
codesign --force --deep --sign - SuperWhisper.app 2>/dev/null || true

echo "🚀 Installing to /Applications/SuperWhisper.app..."
killall SuperWhisper 2>/dev/null || true
sleep 0.5
rm -rf /Applications/SuperWhisper.app
cp -R SuperWhisper.app /Applications/

# Cleanup if temp dir was used
if [[ "$IS_LOCAL" = false ]]; then
    rm -rf "$WORKDIR"
fi

echo ""
echo "✅ SuperWhisper successfully installed to /Applications!"
echo ""
echo "👉 Launching SuperWhisper..."
open /Applications/SuperWhisper.app

echo ""
echo "🎉 Done! Press ⌥ Space (Option + Space) anywhere to dictate."
echo "⚙️  Click the waveform icon in your macOS menu bar to open settings."
echo ""
