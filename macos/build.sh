#!/bin/bash
#
# Build rastertokpsl-re as a universal macOS binary (arm64 + x86_64).
# Requires only the Xcode Command Line Tools -- no CMake, no Homebrew.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/bin/rastertokpsl-re"

say(){ printf '\033[1m==>\033[0m %s\n' "$1"; }
ok(){  printf '    \033[32m%s\033[0m %s\n' "OK" "$1"; }
die(){ printf '\033[31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "This script is for macOS. On Linux use CMake (see the main README)."
command -v cc >/dev/null 2>&1 || die "No compiler found. Run: xcode-select --install"
xcrun --show-sdk-path >/dev/null 2>&1 || die "No SDK found. Run: xcode-select --install"

say "Compiling universal binary (arm64 + x86_64)"
mkdir -p "$ROOT/bin"
cc -O2 -arch arm64 -arch x86_64 -o "$OUT" \
   "$ROOT/src/rastertokpsl.c" \
   "$ROOT/src/halfton.c" \
   "$ROOT/src/libjbig/jbig.c" \
   "$ROOT/src/libjbig/jbig_ar.c" \
   "$ROOT/src/unicode/ConvertUTF.c" \
   "$ROOT/src/main.c" \
   -I"$ROOT/src" -lcups -lcupsimage -lm

chmod 755 "$OUT"
ok "$OUT"
ok "architectures: $(lipo -archs "$OUT")"
echo
say "Next step:  sudo ./macos/install.sh"
