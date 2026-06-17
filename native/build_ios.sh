#!/usr/bin/env bash
# Builds libcurl-impersonate for iOS as a self-contained dylib (dependencies
# static-linked inside, like the Android .so), wraps it in a .framework, and
# packages an .xcframework for static-free embedding into a Flutter app.
#
# By default builds only the SIMULATOR slice (arm64) — enough to validate on a
# simulator with no physical device. Set SDKS="iphonesimulator iphoneos" to also
# build the device slice for release.
#
# Requires macOS with Xcode, plus cmake, ninja, go.
#
# NOTE: authored on a non-macOS host — expect to iterate on the macOS runner.
set -euo pipefail

REF="${CURL_IMPERSONATE_REF:-958d19a967a56286f032f751490134d52e5009f5}"
DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-13.0}"
SDKS="${SDKS:-iphonesimulator}"            # space-separated: iphonesimulator iphoneos
FW_NAME="CurlImpersonate"                   # framework binary name (no hyphens)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK_DIR:-$REPO_ROOT/.native-build}"
SRC="$WORK/curl-impersonate"
OUT="$REPO_ROOT/native/ios"

mkdir -p "$WORK" "$OUT"
if [ ! -d "$SRC/.git" ]; then
  git clone https://github.com/lexiforest/curl-impersonate.git "$SRC"
fi
git -C "$SRC" fetch --depth 1 origin "$REF"
git -C "$SRC" checkout -q "$REF"

# Builds one SDK slice and emits a .framework wrapping the self-contained dylib.
build_framework() {
  local sdk="$1"
  local archs build fwdir dylib
  case "$sdk" in
    iphonesimulator) archs="arm64" ;;     # arm64 simulator on Apple-Silicon runners
    iphoneos)        archs="arm64" ;;
    *) echo "unknown sdk: $sdk" >&2; return 1 ;;
  esac
  build="$WORK/build-ios-$sdk"
  echo "=== configuring iOS slice: $sdk ($archs) ===" >&2
  cmake -S "$SRC" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_ARCHITECTURES="$archs" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DBUILD_SHARED_LIBS=ON >&2
  cmake --build "$build" -j >&2

  dylib="$build/deps/build/curl/lib/libcurl-impersonate.dylib"
  fwdir="$build/$FW_NAME.framework"
  rm -rf "$fwdir"
  mkdir -p "$fwdir"
  cp "$dylib" "$fwdir/$FW_NAME"
  install_name_tool -id "@rpath/$FW_NAME.framework/$FW_NAME" "$fwdir/$FW_NAME"
  cat > "$fwdir/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.bindays.curlimpersonate</string>
  <key>CFBundleName</key><string>$FW_NAME</string>
  <key>CFBundleExecutable</key><string>$FW_NAME</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>MinimumOSVersion</key><string>$DEPLOYMENT_TARGET</string>
</dict></plist>
PLIST
  echo "$fwdir"
}

# (macOS ships bash 3.2 — no associative arrays; track slices with plain vars.)
xcargs=()
first_fw=""
sim_fw=""
for sdk in $SDKS; do
  fw="$(build_framework "$sdk")"
  xcargs+=(-framework "$fw")
  [ -z "$first_fw" ] && first_fw="$fw"
  [ "$sdk" = "iphonesimulator" ] && sim_fw="$fw"
done

# Emit a bare .framework (simulator slice preferred) for single-slice consumers
# that vendor a .framework directly — this avoids CocoaPods' xcframework
# slice-extraction phase, which doesn't run reliably under the app's setup.
bare_fw="${sim_fw:-$first_fw}"
rm -rf "$OUT/$FW_NAME.framework"
cp -R "$bare_fw" "$OUT/$FW_NAME.framework"

# Also emit the .xcframework (needed once device + simulator slices are built).
rm -rf "$OUT/$FW_NAME.xcframework"
xcodebuild -create-xcframework "${xcargs[@]}" -output "$OUT/$FW_NAME.xcframework"

echo "=== output ==="
ls "$OUT"
ls -R "$OUT/$FW_NAME.framework"
