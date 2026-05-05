#!/usr/bin/env bash
#
# Unit tests for the supplementary-file helpers defined in the extract step of
# push-artifacts-to-cdn-task:
#
#   is_supplementary_file()
#   move_supplementary_out()
#
# Run directly:  bash test-supplementary-file-classification.sh
#
set -euo pipefail

PASS=0
FAIL=0

# ── helpers under test (mirrored exactly from the task) ──────────────────
# SYNC-CHECK: keep `is_supplementary_file` and `move_supplementary_out`
# aligned with their definitions in
# `tasks/internal/push-artifacts-to-cdn-task/push-artifacts-to-cdn-task.yaml`
# (extract-and-push-unsigned step).

SUPPLEMENTARY_NAMES="readme license changelog"
SUPPLEMENTARY_EXTS=".md .txt"

is_supplementary_file() {
  local lower
  lower="$(basename "$1")"
  lower="${lower,,}"
  local base ext
  if [[ "$lower" == *.* ]]; then
    base="${lower%.*}"
    ext=".${lower##*.}"
  else
    base="$lower"
    ext=""
  fi
  for name in $SUPPLEMENTARY_NAMES; do
    if [[ "$base" == "$name" ]]; then
      [[ -z "$ext" ]] && return 0
      for allowed_ext in $SUPPLEMENTARY_EXTS; do
        [[ "$ext" == "$allowed_ext" ]] && return 0
      done
    fi
  done
  return 1
}

move_supplementary_out() {
  local src_root="$1"
  local hold_root="$2"
  [ -d "$src_root" ] || return 0
  while IFS= read -r -d '' file; do
    if is_supplementary_file "$file"; then
      local rel="${file#"$src_root"/}"
      local dest="$hold_root/$rel"
      mkdir -p "$(dirname "$dest")"
      mv "$file" "$dest"
    fi
  done < <(find "$src_root" -type f -print0)
}

# ── assert helpers ────────────────────────────────────────────────────────

assert_supplementary() {
  if is_supplementary_file "$1"; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: expected supplementary: $1"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_supplementary() {
  if ! is_supplementary_file "$1"; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: expected NOT supplementary: $1"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  if [ -f "$1" ]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: expected file to exist: $1"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_missing() {
  if [ ! -f "$1" ]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: expected file to be absent: $1"
    FAIL=$((FAIL + 1))
  fi
}

# ── is_supplementary_file ────────────────────────────────────────────────

echo "=== is_supplementary_file ==="

# readme — all valid combos
assert_supplementary "README"
assert_supplementary "readme"
assert_supplementary "Readme"
assert_supplementary "README.md"
assert_supplementary "readme.md"
assert_supplementary "README.MD"
assert_supplementary "readme.MD"
assert_supplementary "README.txt"
assert_supplementary "readme.txt"
assert_supplementary "README.TXT"
assert_supplementary "Readme.Txt"

# license
assert_supplementary "LICENSE"
assert_supplementary "license"
assert_supplementary "License"
assert_supplementary "LICENSE.md"
assert_supplementary "license.md"
assert_supplementary "LICENSE.txt"
assert_supplementary "license.txt"
assert_supplementary "LICENSE.TXT"
assert_supplementary "LICENSE.MD"

# changelog
assert_supplementary "CHANGELOG"
assert_supplementary "changelog"
assert_supplementary "Changelog"
assert_supplementary "CHANGELOG.md"
assert_supplementary "changelog.md"
assert_supplementary "CHANGELOG.txt"
assert_supplementary "changelog.txt"
assert_supplementary "CHANGELOG.TXT"
assert_supplementary "Changelog.MD"

# with path prefix — basename is what matters
assert_supplementary "/some/path/README.md"
assert_supplementary "amd64/LICENSE"
assert_supplementary "/foo/bar/CHANGELOG.txt"

# NOT supplementary — wrong base name
assert_not_supplementary "NOTES.TXT"
assert_not_supplementary "RELEASE_NOTES.TXT"
assert_not_supplementary "INSTALL.md"
assert_not_supplementary "CONTRIBUTING.md"
assert_not_supplementary "setup.cfg"
assert_not_supplementary "Makefile"
assert_not_supplementary "config.json"
assert_not_supplementary "binary-name"

# NOT supplementary — wrong extension
assert_not_supplementary "README.rst"
assert_not_supplementary "README.html"
assert_not_supplementary "LICENSE.html"
assert_not_supplementary "CHANGELOG.rst"
assert_not_supplementary "readme.doc"
assert_not_supplementary "license.pdf"

# NOT supplementary — compound names
assert_not_supplementary "LICENSE-MIT"
assert_not_supplementary "LICENSE-APACHE"
assert_not_supplementary "README-dev.md"

echo ""

# ── move_supplementary_out ────────────────────────────────────────────────

echo "=== move_supplementary_out ==="

T3=$(mktemp -d)
SRC="$T3/unsigned/macos"
HOLD="$T3/supplementary/macos"
mkdir -p "$SRC/amd64" "$SRC/arm64"

echo "binary"    > "$SRC/amd64/my-binary"
echo "readme"    > "$SRC/amd64/README.md"
echo "license"   > "$SRC/amd64/LICENSE"
echo "changelog" > "$SRC/amd64/CHANGELOG.txt"
echo "binary2"   > "$SRC/arm64/my-binary"
echo "readme2"   > "$SRC/arm64/readme.TXT"

move_supplementary_out "$SRC" "$HOLD"

assert_file_exists  "$SRC/amd64/my-binary"
assert_file_exists  "$SRC/arm64/my-binary"
assert_file_missing "$SRC/amd64/README.md"
assert_file_missing "$SRC/amd64/LICENSE"
assert_file_missing "$SRC/amd64/CHANGELOG.txt"
assert_file_missing "$SRC/arm64/readme.TXT"
assert_file_exists  "$HOLD/amd64/README.md"
assert_file_exists  "$HOLD/amd64/LICENSE"
assert_file_exists  "$HOLD/amd64/CHANGELOG.txt"
assert_file_exists  "$HOLD/arm64/readme.TXT"

# restore and verify
SIGNED="$T3/signed/macos"
mkdir -p "$SIGNED/amd64" "$SIGNED/arm64"
echo "signed-binary"  > "$SIGNED/amd64/my-binary"
echo "signed-binary2" > "$SIGNED/arm64/my-binary"

while IFS= read -r -d '' file; do
  rel="${file#"$HOLD"/}"
  dest="$SIGNED/$rel"
  mkdir -p "$(dirname "$dest")"
  mv "$file" "$dest"
done < <(find "$HOLD" -type f -print0)

assert_file_exists  "$SIGNED/amd64/my-binary"
assert_file_exists  "$SIGNED/amd64/README.md"
assert_file_exists  "$SIGNED/amd64/LICENSE"
assert_file_exists  "$SIGNED/amd64/CHANGELOG.txt"
assert_file_exists  "$SIGNED/arm64/my-binary"
assert_file_exists  "$SIGNED/arm64/readme.TXT"

rm -rf "$T3"

echo ""

# ── end-to-end: move → sign → restore ────────────────────────────────────
#
# Simulates the full extract-step flow for a windows component:
#   1. move_supplementary_out: move readme/license/changelog to holding area
#   2. signing host receives only binaries (other non-supplementary files
#      with safe names are also present and would cause a signing failure in
#      production — enforced by the signing tool, not by this task)
#   3. restore supplementary alongside signed binaries

echo "=== end-to-end: move → sign → restore ==="

E2E=$(mktemp -d)
UNSIGNED="$E2E/unsigned/windows"
HOLD_WIN="$E2E/supplementary/windows"
SIGNED_WIN="$E2E/signed/windows"
mkdir -p "$UNSIGNED/amd64"

# RPA binary — must survive round-trip
echo "binary" > "$UNSIGNED/amd64/myproduct-windows-amd64.exe"

# Supplementary files — various valid casings — must survive into final release
echo "r1" > "$UNSIGNED/amd64/README.md"
echo "r2" > "$UNSIGNED/amd64/readme"
echo "l1" > "$UNSIGNED/amd64/LICENSE"
echo "l2" > "$UNSIGNED/amd64/LiCeNsE.TxT"
echo "l3" > "$UNSIGNED/amd64/license.md"
echo "c1" > "$UNSIGNED/amd64/CHANGELOG"
echo "c2" > "$UNSIGNED/amd64/Changelog.txt"
echo "c3" > "$UNSIGNED/amd64/CHANGELOG.MD"
echo "rr" > "$UNSIGNED/amd64/ReadMe"

# ── step 1: move supplementary out ───────────────────────────────────────
move_supplementary_out "$UNSIGNED" "$HOLD_WIN"

# binary still in signing dir
assert_file_exists "$UNSIGNED/amd64/myproduct-windows-amd64.exe"

# all supplementary removed from signing dir
assert_file_missing "$UNSIGNED/amd64/README.md"
assert_file_missing "$UNSIGNED/amd64/readme"
assert_file_missing "$UNSIGNED/amd64/LICENSE"
assert_file_missing "$UNSIGNED/amd64/LiCeNsE.TxT"
assert_file_missing "$UNSIGNED/amd64/license.md"
assert_file_missing "$UNSIGNED/amd64/CHANGELOG"
assert_file_missing "$UNSIGNED/amd64/Changelog.txt"
assert_file_missing "$UNSIGNED/amd64/CHANGELOG.MD"
assert_file_missing "$UNSIGNED/amd64/ReadMe"

# supplementary safely in holding area
assert_file_exists "$HOLD_WIN/amd64/README.md"
assert_file_exists "$HOLD_WIN/amd64/readme"
assert_file_exists "$HOLD_WIN/amd64/LICENSE"
assert_file_exists "$HOLD_WIN/amd64/LiCeNsE.TxT"
assert_file_exists "$HOLD_WIN/amd64/license.md"
assert_file_exists "$HOLD_WIN/amd64/CHANGELOG"
assert_file_exists "$HOLD_WIN/amd64/Changelog.txt"
assert_file_exists "$HOLD_WIN/amd64/CHANGELOG.MD"
assert_file_exists "$HOLD_WIN/amd64/ReadMe"

# ── step 2: signing produces signed output (simulated) ───────────────────
mkdir -p "$SIGNED_WIN/amd64"
echo "signed-binary" > "$SIGNED_WIN/amd64/myproduct-windows-amd64.exe"

# ── step 3: restore supplementary alongside signed binary ────────────────
while IFS= read -r -d '' file; do
  rel="${file#"$HOLD_WIN"/}"
  dest="$SIGNED_WIN/$rel"
  mkdir -p "$(dirname "$dest")"
  mv "$file" "$dest"
done < <(find "$HOLD_WIN" -type f -print0)

# signed binary is present
assert_file_exists "$SIGNED_WIN/amd64/myproduct-windows-amd64.exe"

# all supplementary files restored beside it
assert_file_exists "$SIGNED_WIN/amd64/README.md"
assert_file_exists "$SIGNED_WIN/amd64/readme"
assert_file_exists "$SIGNED_WIN/amd64/LICENSE"
assert_file_exists "$SIGNED_WIN/amd64/LiCeNsE.TxT"
assert_file_exists "$SIGNED_WIN/amd64/license.md"
assert_file_exists "$SIGNED_WIN/amd64/CHANGELOG"
assert_file_exists "$SIGNED_WIN/amd64/Changelog.txt"
assert_file_exists "$SIGNED_WIN/amd64/CHANGELOG.MD"
assert_file_exists "$SIGNED_WIN/amd64/ReadMe"

# holding area is clean after restore
assert_file_missing "$HOLD_WIN/amd64/README.md"
assert_file_missing "$HOLD_WIN/amd64/LICENSE"

rm -rf "$E2E"

echo ""

# ── summary ──────────────────────────────────────────────────────────────

echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All tests passed."
