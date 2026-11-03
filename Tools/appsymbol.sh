#!/bin/bash
# Baut Tools/AppSymbol.swift zusammen mit der Lok aus der App und schreibt das App-Symbol.
set -e
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
sed '/^#Preview/,$d' Gleich/Lok.swift > "$tmp/Lok.swift"
swiftc -parse-as-library -o "$tmp/symbol" Tools/AppSymbol.swift "$tmp/Lok.swift" 2>&1 | grep -v warning || true
"$tmp/symbol" Gleich/Assets.xcassets/AppIcon.appiconset/AppIcon.png
cp Gleich/Assets.xcassets/AppIcon.appiconset/AppIcon.png Gleich/Assets.xcassets/Symbol.imageset/Symbol.png
rm -rf "$tmp"
