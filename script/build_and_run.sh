#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project HalloweenSonos.xcodeproj -scheme HauntMac -configuration Debug -destination 'platform=macOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
open DerivedData/Build/Products/Debug/Haunt.app
