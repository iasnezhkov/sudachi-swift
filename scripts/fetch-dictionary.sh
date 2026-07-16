#!/usr/bin/env bash
# Download a Sudachi system dictionary + place the auxiliary files
# (char.def, unk.def) the runtime needs.
#
# Output layout (in $ROOT/dictionaries/):
#   system_<edition>.dic   (40-700 MB depending on edition)
#   char.def
#   unk.def
#   LEGAL, LICENSE-2.0.txt (SudachiDict attribution — keep these next to the
#                           .dic; they must accompany any redistribution)
#
# Usage:
#   scripts/fetch-dictionary.sh                    # core (default)
#   scripts/fetch-dictionary.sh small              # small (~40 MB)
#   scripts/fetch-dictionary.sh full               # full (~700 MB)
#   scripts/fetch-dictionary.sh core 20260428      # pin a specific version

set -euo pipefail

EDITION="${1:-core}"
VERSION="${2:-latest}"

case "$EDITION" in
  small|core|full) ;;
  *)
    echo "error: edition must be one of: small, core, full (got: $EDITION)" >&2
    exit 1
    ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DICT_DIR="$ROOT/dictionaries"
mkdir -p "$DICT_DIR"

# The CDN serves a "latest" alias as a 301 redirect to the current dated
# release, so the no-argument default always resolves.
DICT_NAME="sudachi-dictionary-${VERSION}-${EDITION}"
URL="https://d2ej7fkh96fzlu.cloudfront.net/sudachidict/${DICT_NAME}.zip"
TARGET_DIC="$DICT_DIR/system_${EDITION}.dic"

if [ -f "$TARGET_DIC" ]; then
  echo "==> $TARGET_DIC already exists, skipping download"
  echo "    delete it to re-fetch"
else
  echo "==> Downloading $URL"
  ZIP="$DICT_DIR/${DICT_NAME}.zip"
  # -f makes an HTTP error (e.g. a typo'd version -> 404) fail the script
  # instead of saving an error page as a "zip".
  curl -fL -o "$ZIP" "$URL"

  echo "==> Unzipping"
  UNZIP_DIR="$DICT_DIR/${DICT_NAME}"
  rm -rf "$UNZIP_DIR"
  unzip -q "$ZIP" -d "$DICT_DIR"

  # The zip extracts to a dated directory like
  # sudachi-dictionary-20260428/system_<edition>.dic, not the literal
  # ${VERSION} we passed. Find what actually came out.
  ACTUAL_DIR="$(find "$DICT_DIR" -maxdepth 1 -type d -name 'sudachi-dictionary-*' | head -1)"
  if [ -z "$ACTUAL_DIR" ]; then
    echo "error: could not locate unzipped dictionary directory" >&2
    exit 1
  fi
  mv "$ACTUAL_DIR/system_${EDITION}.dic" "$TARGET_DIC"

  # Keep the dictionary's attribution files next to the .dic — SudachiDict's
  # LEGAL notice must accompany the data if you redistribute it (see NOTICE).
  for f in LEGAL LICENSE-2.0.txt; do
    [ -f "$ACTUAL_DIR/$f" ] && mv "$ACTUAL_DIR/$f" "$DICT_DIR/$f"
  done

  echo "==> Cleaning up"
  rm -f "$ZIP"
  rm -rf "$ACTUAL_DIR"
fi

# char.def + unk.def live in the sudachi.rs repo (Apache-2.0 with the
# same redistribution license as the dictionary itself).
RESOURCES_SRC="$ROOT/third_party/sudachi.rs/resources"
for f in char.def unk.def; do
  if [ ! -f "$DICT_DIR/$f" ] || [ "$RESOURCES_SRC/$f" -nt "$DICT_DIR/$f" ]; then
    cp "$RESOURCES_SRC/$f" "$DICT_DIR/$f"
    echo "==> Copied $f"
  fi
done

echo ""
echo "==> Done. Dictionary contents:"
ls -lh "$DICT_DIR/"
echo ""
echo "    Use in Swift:"
echo "      let dict = try SudachiDictionary("
echo "        systemDictPath: \"\$REPO/dictionaries/system_${EDITION}.dic\","
echo "        userDictPaths: [],"
echo "        resourceDir: \"\$REPO/dictionaries\""
echo "      )"
