#!/usr/bin/env bash
# Build Sudachi.xcframework from the Rust workspace (Apple Silicon only).
#
# Outputs:
#   build/Sudachi.xcframework  — binary target for SPM: one dynamic
#     sudachi_swiftFFI.framework per slice, each packaged with its own .dSYM
#   build/generated/sudachi_swiftFFI.{h,modulemap}  — C header + modulemap
#   swift/Sudachi/Sources/Sudachi/Sudachi.swift — Swift bindings
#
# Requires: rustup with the Apple targets below installed; Xcode CLT. The
# pinned sudachi.rs sources are fetched automatically if missing.

set -euo pipefail

# Ensure cargo is on PATH even when invoked from non-interactive shells.
if [ -f "$HOME/.cargo/env" ]; then
  # shellcheck source=/dev/null
  source "$HOME/.cargo/env"
fi

# A Homebrew `rust` earlier on PATH shadows rustup and has no Apple targets.
if command -v rustup >/dev/null 2>&1; then
  PATH="$(dirname "$(rustup which rustc)"):$PATH"
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
LIB_NAME="sudachi_swift"

# Named after the module the generated bindings import (`import sudachi_swiftFFI`).
FW_NAME="${LIB_NAME}FFI"
FW_BUNDLE_ID="io.github.iasnezhkov.sudachi-swift.ffi"

# Keep in sync with the platforms in Package.swift.
IOS_MIN="17.0"
MACOS_MIN="14.0"

CRATE_VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' "$ROOT/Cargo.toml" | head -n1)"
if [ -z "$CRATE_VERSION" ]; then
  echo "error: no workspace version found in $ROOT/Cargo.toml" >&2
  exit 1
fi
# CFBundleShortVersionString only accepts dotted integers.
FW_SHORT_VERSION="${CRATE_VERSION%%-*}"
FW_SHORT_VERSION="${FW_SHORT_VERSION%%+*}"

# Apple Silicon only: arm64 device, arm64 simulator, arm64 macOS. The x86_64
# (Intel) slices are intentionally dropped — it roughly halves the artifact, and
# Intel Macs can build from source if ever needed.
SLICES=(
  "aarch64-apple-ios ios iphoneos"
  "aarch64-apple-ios-sim sim iphonesimulator"
  "aarch64-apple-darwin macos macosx"
)

mkdir -p "$BUILD"

# The wrapper crate has a path dependency on third_party/sudachi.rs, which is
# fetched on demand at a pinned commit rather than vendored as a submodule
# (see scripts/fetch-sudachi-rs.sh). No-op once it is present at the pin.
"$ROOT/scripts/fetch-sudachi-rs.sh"

echo "==> Building Rust cdylibs for Apple targets (arm64)"
cd "$ROOT"
for slice in "${SLICES[@]}"; do
  read -r triple _ platform <<<"$slice"
  case "$platform" in
    macosx) deployment="MACOSX_DEPLOYMENT_TARGET=$MACOS_MIN" ;;
    iphoneos | iphonesimulator) deployment="IPHONEOS_DEPLOYMENT_TARGET=$IOS_MIN" ;;
    *)
      echo "error: unknown platform '$platform'" >&2
      exit 1
      ;;
  esac
  echo "    [$triple]"
  env "$deployment" cargo build -p sudachi-swift-uniffi --release --target "$triple"
done

echo "==> Generating Swift bindings"
cargo run --features cli --bin uniffi-bindgen --release -- generate \
  "$ROOT/crates/sudachi-swift-uniffi/src/${LIB_NAME}.udl" \
  --language swift \
  --out-dir "$BUILD/generated"

SWIFT_OUT="$ROOT/swift/Sudachi/Sources/Sudachi"
mkdir -p "$SWIFT_OUT"
cp "$BUILD/generated/${LIB_NAME}.swift" "$SWIFT_OUT/Sudachi.swift"

# Dynamic, not static: Xcode's previews JIT cannot materialise symbols out of
# static-archive members, so a statically linked consumer loses every #Preview
# that touches the tokenizer. verify_slice asserts what that relies on.
FRAMEWORKS_DIR="$BUILD/frameworks"
rm -rf "$FRAMEWORKS_DIR"

DECLARED_SYMBOLS="$BUILD/declared-ffi-symbols.txt"
grep -oE '\b(ffi_|uniffi_)'"${LIB_NAME}"'_[A-Za-z0-9_]+' \
  "$BUILD/generated/${FW_NAME}.h" | sort -u >"$DECLARED_SYMBOLS"

write_framework_modulemap() {  # <modules-dir>
  local src="$BUILD/generated/${FW_NAME}.modulemap"
  # Derived, not hand-copied, so anything UniFFI adds to it carries over.
  if ! head -n1 "$src" | grep -qE "^module ${FW_NAME} \{"; then
    echo "error: unexpected first line in $src — cannot derive a framework modulemap:" >&2
    head -n1 "$src" >&2
    exit 1
  fi
  sed '1s/^module /framework module /' "$src" >"$1/module.modulemap"
}

write_info_plist() {  # <plist-path> <platform>
  local platform="$2" min_key min_value supported_platform
  case "$platform" in
    macosx) min_key="LSMinimumSystemVersion" min_value="$MACOS_MIN" supported_platform="MacOSX" ;;
    iphoneos) min_key="MinimumOSVersion" min_value="$IOS_MIN" supported_platform="iPhoneOS" ;;
    iphonesimulator) min_key="MinimumOSVersion" min_value="$IOS_MIN" supported_platform="iPhoneSimulator" ;;
    *)
      echo "error: unknown platform '$platform'" >&2
      exit 1
      ;;
  esac
  cat >"$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>${FW_BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${FW_NAME}</string>
    <key>CFBundleName</key><string>${FW_NAME}</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>${FW_SHORT_VERSION}</string>
    <key>CFBundleVersion</key><string>${FW_SHORT_VERSION}</string>
    <key>CFBundleSupportedPlatforms</key><array><string>${supported_platform}</string></array>
    <key>${min_key}</key><string>${min_value}</string>
</dict>
</plist>
EOF
}

verify_slice() {  # <framework-path> <binary-path>
  local dsym="$1.dSYM" bin="$2" missing
  # No `grep -q` in these pipelines: under `set -o pipefail` its early exit
  # SIGPIPEs the producer and fails the pipeline even on a match.
  if ! file "$bin" | grep "dynamically linked shared library" >/dev/null; then
    echo "error: $bin is not a dylib (the previews JIT cannot link static archives)." >&2
    exit 1
  fi
  if otool -l "$bin" | grep "segname __LLVM" >/dev/null; then
    echo "error: $bin carries embedded LLVM bitcode (__LLVM segment), which" >&2
    echo "       crashes Xcode's preview agent in consuming apps." >&2
    exit 1
  fi
  missing="$(comm -23 "$DECLARED_SYMBOLS" \
    <(nm -g "$bin" 2>/dev/null | awk 'NF == 3 { print $3 }' | sed 's/^_//' | sort -u))"
  if [ -n "$missing" ]; then
    echo "error: $bin is missing FFI symbols the generated header declares:" >&2
    echo "$missing" | sed 's/^/       /' >&2
    exit 1
  fi
  if [ ! -d "$dsym" ]; then
    echo "error: $dsym is missing — dsymutil produced no debug symbols." >&2
    echo "       Check [profile.release] in Cargo.toml: debug on, strip off." >&2
    exit 1
  fi
  if [ "$(dwarfdump --uuid "$bin" | awk '{ print $2 }')" \
    != "$(dwarfdump --uuid "$dsym" | awk '{ print $2 }')" ]; then
    echo "error: $dsym does not match the UUID of the binary that ships." >&2
    exit 1
  fi
}

build_framework() {  # <target-triple> <slice-dir> <platform>
  local triple="$1" dir="$2" platform="$3"
  local src="$ROOT/target/$triple/release/lib${LIB_NAME}.dylib"
  local fw="$FRAMEWORKS_DIR/$dir/${FW_NAME}.framework"
  local binary headers modules plist install_id

  if [ "$platform" = "macosx" ]; then
    # macOS frameworks are versioned bundles; codesign rejects the flat layout.
    mkdir -p "$fw/Versions/A/Headers" "$fw/Versions/A/Modules" "$fw/Versions/A/Resources"
    ln -s A "$fw/Versions/Current"
    ln -s "Versions/Current/${FW_NAME}" "$fw/${FW_NAME}"
    ln -s Versions/Current/Headers "$fw/Headers"
    ln -s Versions/Current/Modules "$fw/Modules"
    ln -s Versions/Current/Resources "$fw/Resources"
    binary="$fw/Versions/A/${FW_NAME}"
    headers="$fw/Versions/A/Headers"
    modules="$fw/Versions/A/Modules"
    plist="$fw/Versions/A/Resources/Info.plist"
    install_id="@rpath/${FW_NAME}.framework/Versions/A/${FW_NAME}"
  else
    mkdir -p "$fw/Headers" "$fw/Modules"
    binary="$fw/${FW_NAME}"
    headers="$fw/Headers"
    modules="$fw/Modules"
    plist="$fw/Info.plist"
    install_id="@rpath/${FW_NAME}.framework/${FW_NAME}"
  fi

  cp "$src" "$binary"
  chmod u+w "$binary"
  install_name_tool -id "$install_id" "$binary"
  # After install_name_tool so the .dSYM matches the shipped UUID, before the
  # strip that removes the DWARF it lifts.
  dsymutil "$binary" -o "$fw.dSYM"
  strip -S -x "$binary"

  cp "$BUILD/generated/${FW_NAME}.h" "$headers/${FW_NAME}.h"
  write_framework_modulemap "$modules"
  write_info_plist "$plist" "$platform"
  # Xcode re-signs with the app's identity on embed; this is for local test runs.
  codesign --force --sign - "$fw"

  verify_slice "$fw" "$binary"
}

echo "==> Assembling dynamic frameworks (verifying each slice)"
XCF_ARGS=()
for slice in "${SLICES[@]}"; do
  read -r triple dir platform <<<"$slice"
  build_framework "$triple" "$dir" "$platform"
  # Each -debug-symbols binds to the -framework preceding it; paths are absolute.
  XCF_ARGS+=(
    -framework "$FRAMEWORKS_DIR/$dir/${FW_NAME}.framework"
    -debug-symbols "$FRAMEWORKS_DIR/$dir/${FW_NAME}.framework.dSYM"
  )
done

echo "==> Building xcframework (ios device + ios sim + macOS, all arm64)"
XCF="$BUILD/Sudachi.xcframework"
rm -rf "$XCF"
xcodebuild -create-xcframework "${XCF_ARGS[@]}" -output "$XCF"

echo ""
echo "==> Done."
echo "    Swift sources:    swift/Sudachi/Sources/Sudachi/Sudachi.swift"
echo "    xcframework:      build/Sudachi.xcframework"
echo ""
du -sh "$XCF"
