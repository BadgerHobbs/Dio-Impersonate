#!/usr/bin/env bash
# Cross-compiles libcurl-impersonate for one Android ABI and emits the stripped
# shared library (+ the matching libc++_shared.so) into native/android/<abi>/.
#
# Requires: cmake, ninja, go, and a host C/C++ toolchain; ANDROID_NDK_HOME set
# to an NDK r26+ install.
#
# Usage: native/build_android.sh <abi>        e.g. arm64-v8a | armeabi-v7a | x86_64
set -euo pipefail

ABI="${1:?usage: build_android.sh <abi>}"
API="${ANDROID_API:-21}"
REF="${CURL_IMPERSONATE_REF:-958d19a967a56286f032f751490134d52e5009f5}"
NDK="${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME to an NDK r26+ install}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK_DIR:-$REPO_ROOT/.native-build}"
SRC="$WORK/curl-impersonate"
BUILD="$WORK/build-android-$ABI"
OUT="$REPO_ROOT/native/android/$ABI"

case "$ABI" in
  arm64-v8a)   TRIPLE=aarch64-linux-android ;;
  armeabi-v7a) TRIPLE=arm-linux-androideabi ;;
  x86_64)      TRIPLE=x86_64-linux-android ;;
  x86)         TRIPLE=i686-linux-android ;;
  *) echo "unknown ABI: $ABI" >&2; exit 1 ;;
esac

mkdir -p "$WORK"
if [ ! -d "$SRC/.git" ]; then
  git clone https://github.com/lexiforest/curl-impersonate.git "$SRC"
fi
git -C "$SRC" fetch --depth 1 origin "$REF"
git -C "$SRC" checkout -q "$REF"

echo "=== configuring (android $ABI, API $API, curl-impersonate $REF) ==="
cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=Android \
  -DCMAKE_ANDROID_NDK="$NDK" \
  -DCMAKE_ANDROID_ARCH_ABI="$ABI" \
  -DCMAKE_SYSTEM_VERSION="$API"

echo "=== building ==="
cmake --build "$BUILD" -j

SO="$BUILD/deps/build/curl/lib/libcurl-impersonate.so"
TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
mkdir -p "$OUT"
cp "$SO" "$OUT/libcurl-impersonate.so"
"$TC/bin/llvm-strip" --strip-unneeded "$OUT/libcurl-impersonate.so"
cp "$TC/sysroot/usr/lib/$TRIPLE/libc++_shared.so" "$OUT/libc++_shared.so"

echo "=== output ($OUT) ==="
ls -la "$OUT"
