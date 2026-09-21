#!/bin/bash
# create-xcode-project.sh — Generate an Xcode project from the Swift package
# Run once from the RedstoneSetup/ directory:  ./create-xcode-project.sh
# Then: open RedstoneSetup.xcodeproj

set -e

echo "📦 Generating Xcode project..."
swift package generate-xcodeproj 2>/dev/null || {
    # Newer Swift: use -open flag approach
    echo "Trying alternative approach..."
    open Package.swift
    echo "✅ Opened Package.swift in Xcode. Xcode will handle project generation."
    exit 0
}

echo "✅ Xcode project created!"
echo "Opening in Xcode..."
open RedstoneSetup.xcodeproj
