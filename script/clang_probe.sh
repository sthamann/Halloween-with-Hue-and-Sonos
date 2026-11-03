#!/usr/bin/env bash
# Workaround for Xcode's verbose compiler-probe pipe deadlock on this Mac.
# Actual compilation uses Apple's compiler unchanged. Only -v on -dM probes is removed.
set -euo pipefail
CLANG_BIN="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
if [[ " $* " == *" -dM "* && " $* " == *" -v "* ]]; then
  args=()
  for arg in "$@"; do [[ "$arg" == '-v' ]] || args+=("$arg"); done
  exec "$CLANG_BIN" "${args[@]}"
fi
exec "$CLANG_BIN" "$@"
