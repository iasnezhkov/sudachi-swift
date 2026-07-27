#!/usr/bin/env bash
# Check out the pinned sudachi.rs source into third_party/sudachi.rs.
#
# sudachi.rs used to be a git submodule. It deliberately is not one any more:
# SwiftPM runs `git submodule update --init --recursive` on every fresh checkout
# of a package, so every consumer of this package cloned the entire sudachi.rs
# history before compiling a single Swift file — for sources nothing in the SPM
# graph ever reads (the package consumes a prebuilt .xcframework plus
# swift/Sudachi/…).
#
# The Rust wrapper crate still needs the source (path dependency in
# crates/sudachi-swift-uniffi/Cargo.toml), and scripts/fetch-dictionary.sh needs
# its resources/, so it is fetched on demand here instead: shallow and pinned.
#
# The pin lives in third_party/sudachi.rs.pin (one full 40-character commit SHA).
#
# Usage: scripts/fetch-sudachi-rs.sh
# Env:   SUDACHI_RS_REPO — override the clone URL (default: upstream GitHub)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/third_party/sudachi.rs"
PIN_FILE="$ROOT/third_party/sudachi.rs.pin"
REPO="${SUDACHI_RS_REPO:-https://github.com/WorksApplications/sudachi.rs.git}"

if [ ! -f "$PIN_FILE" ]; then
  echo "error: pin file not found: $PIN_FILE" >&2
  exit 1
fi

# First non-empty, non-comment line is the commit SHA.
PIN="$(grep -vE '^[[:space:]]*(#|$)' "$PIN_FILE" | head -n1 | tr -d '[:space:]')"
if ! [[ "$PIN" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: $PIN_FILE must hold a full 40-character commit SHA (got: '$PIN')" >&2
  exit 1
fi

abs_path() { (cd "$1" >/dev/null 2>&1 && pwd -P); }

# `git -C <dir>` walks *up* to the enclosing repository when <dir> is not one
# itself — and $DEST sits inside this repo, so an empty or missing directory
# there would otherwise resolve to the superproject and we would fetch and
# check out sudachi.rs on top of sudachi-swift. A path therefore only counts as
# sudachi.rs' checkout when it is the repository root itself.
dest_is_repo_root() {
  [ -d "$DEST" ] || return 1
  local top
  top="$(git -C "$DEST" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "$top" ] && [ "$(abs_path "$top")" = "$(abs_path "$DEST")" ]
}

head_sha() {
  dest_is_repo_root || return 0
  git -C "$DEST" rev-parse HEAD 2>/dev/null || true
}

CURRENT="$(head_sha)"
if [ "$CURRENT" = "$PIN" ]; then
  echo "==> sudachi.rs already at $PIN"
  exit 0
fi

if [ -n "$CURRENT" ]; then
  # Includes the legacy submodule layout, where .git is a gitlink file pointing
  # into the superproject's .git/modules — that keeps working as a plain
  # repository, so an existing checkout is reused rather than re-downloaded.
  echo "==> sudachi.rs is at $CURRENT, moving to $PIN"
else
  if [ -e "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
    echo "==> $DEST exists but is not a sudachi.rs checkout — replacing it"
    rm -rf "$DEST"
  fi
  mkdir -p "$DEST"
  git init -q "$DEST"
fi

# Belt and braces: never let the fetch/checkout below touch a parent repository.
if ! dest_is_repo_root; then
  echo "error: $DEST is not a git repository root — refusing to continue" >&2
  exit 1
fi

if git -C "$DEST" remote get-url origin >/dev/null 2>&1; then
  git -C "$DEST" remote set-url origin "$REPO"
else
  git -C "$DEST" remote add origin "$REPO"
fi

# GitHub serves an arbitrary commit by SHA, which keeps this to a single
# shallow object transfer. Fall back to a full fetch on hosts/mirrors that
# don't (uploadpack.allowAnySHA1InWant disabled).
echo "==> Fetching sudachi.rs $PIN from $REPO"
if ! git -C "$DEST" fetch --depth 1 origin "$PIN" 2>/dev/null; then
  echo "    shallow fetch by SHA unavailable — falling back to a full fetch"
  git -C "$DEST" fetch origin
fi
git -C "$DEST" checkout -q --detach "$PIN"

LANDED="$(head_sha)"
if [ "$LANDED" != "$PIN" ]; then
  echo "error: checkout landed on '$LANDED', expected $PIN" >&2
  exit 1
fi
echo "==> sudachi.rs at $PIN"
