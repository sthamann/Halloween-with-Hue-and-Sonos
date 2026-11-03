#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
MODE="${1:-simulator}"
if [[ "$MODE" == simulator ]]; then DEST='generic/platform=iOS Simulator'; else DEST='generic/platform=iOS'; fi
FLAGS=(CODE_SIGNING_ALLOWED=NO)
if [[ -n "${HAUNT_TEAM_ID:-}" && "$MODE" != simulator ]]; then FLAGS=(CODE_SIGNING_ALLOWED=YES "DEVELOPMENT_TEAM=$HAUNT_TEAM_ID"); fi
if [[ "${HAUNT_QUIET_CLANG_PROBE:-1}" == 1 ]]; then FLAGS+=("CC=$ROOT_DIR/script/clang_probe.sh"); fi
xcodebuild -quiet -project HalloweenSonos.xcodeproj -scheme HauntIOS -destination "$DEST" -derivedDataPath "$ROOT_DIR/DerivedData" "${FLAGS[@]}" build
printf 'Built: %s\n' "$ROOT_DIR/DerivedData/Build/Products/Debug-$(if [[ "$MODE" == simulator ]]; then echo iphonesimulator; else echo iphoneos; fi)/Haunt.app"
