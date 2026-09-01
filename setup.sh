#!/bin/bash

# Aster VPN Project Setup Script
# Usage: ./setup.sh

echo "🚀 Initializing Aster VPN Project..."

# Check if XcodeGen is installed
if ! command -v xcodegen &> /dev/null; then
    echo "⚠️  XcodeGen not found. Installing via Homebrew..."
    if ! command -v brew &> /dev/null; then
        echo "❌ Homebrew not found. Please install Homebrew or XcodeGen manually."
        exit 1
    fi
    brew install xcodegen
fi

# Generate the .xcodeproj
echo "🛠  Generating Xcode Project..."
xcodegen generate

echo "✅ Project generated successfully!"
echo "👉 Open 'Aster.xcodeproj' to start coding."
echo "⚠️  Note: You must set your 'Development Team' in the project settings manually."
