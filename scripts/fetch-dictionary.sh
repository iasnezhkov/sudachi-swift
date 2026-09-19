#!/usr/bin/env bash
# Download a Sudachi system dictionary + place the auxiliary files
# (char.def, unk.def, rewrite.def) the runtime needs.
#
# Output layout (in $ROOT/dictionaries/):
#   system_<edition>.dic   (40-700 MB depending on edition)
#   char.def
#   unk.def
#   rewrite.def
#   LEGAL, LICENSE-2.0.txt (SudachiDict attribution — keep these next to the
#                           .dic; they must accompany any redistribution)
#
# Usage:
#   scripts/fetch-dictionary.sh                    # core (default)
#   scripts/fetch-dictionary.sh small              # small (~40 MB)
#   scripts/fetch-dictionary.sh full               # full (~700 MB)
#   scripts/fetch-dictionary.sh core 20260723      # pin a specific version
# Env:
#   SUDACHI_DICT_FORMAT — binary dictionary format, v1 (default) or v0

set -euo pipefail

EDITION="${1:-core}"
VERSION="${2:-latest}"

# Which binary format we need is dictated by third_party/sudachi.rs.pin, not by
# the caller: sudachi.rs 0.7 reads only "v1" and rejects v0 outright ("Invalid
# description: V0 version"), while 0.6.x reads only v0. Keep this in step with
# the pin. v1 builds sit under an extra /v1/ path segment on the same CDN —
# published since 2026-07-27 but deliberately absent from the raw index page
# (SudachiDict#61), so they resolve by URL only.
FORMAT="${SUDACHI_DICT_FORMAT:-v1}"
case "$FORMAT" in
  v1) FORMAT_PATH="v1/" ;;
  v0) FORMAT_PATH="" ;;
  *)
    echo "error: SUDACHI_DICT_FORMAT must be v0 or v1 (got: $FORMAT)" >&2
    exit 1
    ;;
esac

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
URL="https://d2ej7fkh96fzlu.cloudfront.net/sudachidict/${FORMAT_PATH}${DICT_NAME}.zip"
TARGET_DIC="$DICT_DIR/system_${EDITION}.dic"

# A v1 dictionary starts with the ASCII magic "SudachiBinaryDic"; a v0 one
# starts with a binary version word. An existing .dic in the other format is
# useless to the pinned engine and would only surface as a confusing load
# error, so treat it as absent and re-fetch.
dic_format() {
  if [ "$(head -c 16 "$1" 2>/dev/null)" = "SudachiBinaryDic" ]; then
    echo "v1"
  else
    echo "v0"
  fi
}

if [ -f "$TARGET_DIC" ] && [ "$(dic_format "$TARGET_DIC")" != "$FORMAT" ]; then
  echo "==> $TARGET_DIC is $(dic_format "$TARGET_DIC"), need $FORMAT — re-fetching"
  rm -f "$TARGET_DIC"
fi

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
  # sudachi-dictionary-20260723/system_<edition>.dic, not the literal
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

# char.def, unk.def and rewrite.def live in the sudachi.rs repo (Apache-2.0 with
# the same redistribution license as the dictionary itself). Those sources are
# fetched on demand at a pinned commit, so pull them if this is a fresh clone.
#
# rewrite.def joined the list with 0.7: its DefaultInputTextPlugin resolves the
# file through the config PathResolver, so a resource dir without it fails the
# whole dictionary load ("Failed to resolve relative path rewrite.def").
RESOURCES_SRC="$ROOT/third_party/sudachi.rs/resources"
if [ ! -d "$RESOURCES_SRC" ]; then
  "$ROOT/scripts/fetch-sudachi-rs.sh"
fi
# Compare contents, not mtimes: a checkout can hand us a file older than the
# copy already sitting in dictionaries/, and the stale copy then survives every
# re-run. That is not hypothetical — it is how an outdated char.def (retired
# NOOOVBOW2 category) kept breaking 0.7 loads long after the pin had moved.
for f in char.def unk.def rewrite.def; do
  if ! cmp -s "$RESOURCES_SRC/$f" "$DICT_DIR/$f"; then
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
