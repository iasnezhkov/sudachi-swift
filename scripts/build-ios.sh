#!/usr/bin/env bash
# Build SujiSudachi.xcframework from the Rust workspace.
#
# Outputs:
#   build/SujiSudachi.xcframework  — binary target for SPM
#   build/generated/SujiSudachiFFI.{h,modulemap}  — C header + modulemap
#   swift/SujiSudachi/Sources/SujiSudachi/SujiSudachi.swift — Swift bindings
#
# Requires: rustup with aarch64-apple-ios, aarch64-apple-ios-sim,
# x86_64-apple-ios targets installed; Xcode command line tools.

set -euo pipefail

# Ensure cargo is on PATH even when invoked from non-interactive shells.
if [ -f "$HOME/.cargo/env" ]; then
  # shellcheck source=/dev/null
  source "$HOME/.cargo/env"
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
LIB_NAME="suji_sudachi"
STATIC_LIB="lib${LIB_NAME}.a"

mkdir -p "$BUILD"

echo "==> Building Rust staticlibs for all Apple targets"
cd "$ROOT"
for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios aarch64-apple-darwin; do
  echo "    [$target]"
  cargo build -p suji-sudachi-uniffi --release --target "$target"
done

echo "==> Generating Swift bindings"
cargo run --features cli --bin uniffi-bindgen --release -- generate \
  "$ROOT/crates/suji-sudachi-uniffi/src/${LIB_NAME}.udl" \
  --language swift \
  --out-dir "$BUILD/generated"

# UniFFI generates: <lib>.swift, <lib>FFI.h, <lib>FFI.modulemap
# The .modulemap must be named "module.modulemap" inside the framework headers dir.
SWIFT_OUT="$ROOT/swift/SujiSudachi/Sources/SujiSudachi"
mkdir -p "$SWIFT_OUT"
cp "$BUILD/generated/${LIB_NAME}.swift" "$SWIFT_OUT/SujiSudachi.swift"

HEADERS_DIR="$BUILD/headers"
rm -rf "$HEADERS_DIR"
mkdir -p "$HEADERS_DIR"
cp "$BUILD/generated/${LIB_NAME}FFI.h" "$HEADERS_DIR/${LIB_NAME}FFI.h"
# Rename modulemap to canonical name expected by xcframework
cp "$BUILD/generated/${LIB_NAME}FFI.modulemap" "$HEADERS_DIR/module.modulemap"

echo "==> Lipo'ing simulator slices"
LIPO_SIM="$BUILD/libsuji_sudachi-sim.a"
lipo -create \
  "$ROOT/target/aarch64-apple-ios-sim/release/$STATIC_LIB" \
  "$ROOT/target/x86_64-apple-ios/release/$STATIC_LIB" \
  -output "$LIPO_SIM"

echo "==> Building xcframework (ios device + ios sim + macOS arm64)"
XCF="$BUILD/SujiSudachi.xcframework"
rm -rf "$XCF"
xcodebuild -create-xcframework \
  -library "$ROOT/target/aarch64-apple-ios/release/$STATIC_LIB" \
  -headers "$HEADERS_DIR" \
  -library "$LIPO_SIM" \
  -headers "$HEADERS_DIR" \
  -library "$ROOT/target/aarch64-apple-darwin/release/$STATIC_LIB" \
  -headers "$HEADERS_DIR" \
  -output "$XCF"

echo ""
echo "==> Done."
echo "    Swift sources:    swift/SujiSudachi/Sources/SujiSudachi/SujiSudachi.swift"
echo "    xcframework:      build/SujiSudachi.xcframework"
echo ""
du -sh "$XCF"
