#!/usr/bin/env bats

setup() {
  export TEST_TEMP_DIR=$(mktemp -d)
  export MOCK_BIN="$TEST_TEMP_DIR/mock-bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"

  export SCRIPT_GET_URLS="$TEST_TEMP_DIR/get-image-urls.sh"
  export SCRIPT_EXTRACT="$TEST_TEMP_DIR/extract-artifacts.sh"

  export TRUSTED_ARTIFACTS_EXTRACT_DIR="$TEST_TEMP_DIR/extract"
  export SNAPSHOT_PATH="snapshot.json"
  export IMAGES_TXT="$TEST_TEMP_DIR/images.txt"
  export FILES_DIR="$TEST_TEMP_DIR/files"

  mkdir -p "$TRUSTED_ARTIFACTS_EXTRACT_DIR"
  mkdir -p "$FILES_DIR"

  # Embed get-image-urls script
  cat << 'SCRIPT_EOF' > "$SCRIPT_GET_URLS"
#!/usr/bin/env bash
set -euo pipefail

< "${TRUSTED_ARTIFACTS_EXTRACT_DIR}/${SNAPSHOT_PATH}" jq -r '.components[].containerImage' | tee "${IMAGES_TXT}"
SCRIPT_EOF
  chmod +x "$SCRIPT_GET_URLS"

  # Embed extract-artifacts script
  cat << 'SCRIPT_EOF' > "$SCRIPT_EXTRACT"
#!/usr/bin/env bash
set -euo pipefail

AUTHFILE='/tmp/auth.json'
mkdir -p "${FILES_DIR}"
while read -r IMAGE; do
  echo "Processing ${IMAGE}"
  select-oci-auth "${IMAGE}" > "${AUTHFILE}"
  retry oras pull --registry-config "${AUTHFILE}" "${IMAGE}" -o "${FILES_DIR}"
done < "${IMAGES_TXT}"

echo "Extracted files:"
ls -la "${FILES_DIR}"
SCRIPT_EOF
  
  # Replace hardcoded /tmp/auth.json with a temp path to avoid permission issues
  sed -i'' -e "s|/tmp/auth.json|$TEST_TEMP_DIR/auth.json|g" "$SCRIPT_EXTRACT"
  chmod +x "$SCRIPT_EXTRACT"

  # Mock select-oci-auth
  cat << 'EOF' > "$MOCK_BIN/select-oci-auth"
#!/usr/bin/env bash
if [[ "$SELECT_FAIL" == "true" ]]; then
  echo "select-oci-auth failed" >&2
  exit 1
fi
echo '{"auths": {}}'
EOF
  chmod +x "$MOCK_BIN/select-oci-auth"

  # Mock retry
  cat << 'EOF' > "$MOCK_BIN/retry"
#!/usr/bin/env bash
if [[ "$RETRY_FAIL" == "true" ]]; then
  echo "retry failed" >&2
  exit 1
fi
"$@"
EOF
  chmod +x "$MOCK_BIN/retry"

  # Mock oras
  cat << 'EOF' > "$MOCK_BIN/oras"
#!/usr/bin/env bash
if [[ "$1" == "pull" ]]; then
  if [[ "$ORAS_FAIL" == "true" ]]; then
    echo "oras pull failed" >&2
    exit 1
  fi
  OUTDIR=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-o" ]]; then
      OUTDIR="$2"
      shift 2
    else
      shift 1
    fi
  done
  if [[ -n "$OUTDIR" ]]; then
    touch "$OUTDIR/dummy.txt"
  fi
  echo "Pulled image"
  exit 0
else
  echo "Unknown oras command" >&2
  exit 1
fi
EOF
  chmod +x "$MOCK_BIN/oras"
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

# ── Suite: get-image-urls ────────────────────────────────

@test "get-image-urls: happy path extracts container images" {
  cat << 'EOF' > "${TRUSTED_ARTIFACTS_EXTRACT_DIR}/${SNAPSHOT_PATH}"
{
  "components": [
    {"containerImage": "registry.com/image1:latest"},
    {"containerImage": "registry.com/image2:latest"}
  ]
}
EOF
  run "$SCRIPT_GET_URLS"
  [ "$status" -eq 0 ]
  [ -f "$IMAGES_TXT" ]
  run cat "$IMAGES_TXT"
  [[ "$output" == *"registry.com/image1:latest"* ]]
  [[ "$output" == *"registry.com/image2:latest"* ]]
}

@test "get-image-urls: error when snapshot file is missing" {
  run "$SCRIPT_GET_URLS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No such file or directory"* ]]
}

@test "get-image-urls: error when snapshot JSON is invalid" {
  echo "invalid json" > "${TRUSTED_ARTIFACTS_EXTRACT_DIR}/${SNAPSHOT_PATH}"
  run "$SCRIPT_GET_URLS"
  [ "$status" -ne 0 ]
  [[ "$output" == *"parse error"* ]] || [[ "$output" == *"Invalid numeric literal"* ]]
}

@test "get-image-urls: edge case with empty components array" {
  cat << 'EOF' > "${TRUSTED_ARTIFACTS_EXTRACT_DIR}/${SNAPSHOT_PATH}"
{
  "components": []
}
EOF
  run "$SCRIPT_GET_URLS"
  [ "$status" -eq 0 ]
  [ -f "$IMAGES_TXT" ]
  [ ! -s "$IMAGES_TXT" ] # file should be empty
}

@test "get-image-urls: edge case with missing components array" {
  cat << 'EOF' > "${TRUSTED_ARTIFACTS_EXTRACT_DIR}/${SNAPSHOT_PATH}"
{
  "other": "data"
}
EOF
  run "$SCRIPT_GET_URLS"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Cannot iterate over null"* ]]
}

@test "get-image-urls: edge case with missing containerImage field" {
  cat << 'EOF' > "${TRUSTED_ARTIFACTS_EXTRACT_DIR}/${SNAPSHOT_PATH}"
{
  "components": [
    {"other": "data"}
  ]
}
EOF
  run "$SCRIPT_GET_URLS"
  [ "$status" -eq 0 ]
  [ -f "$IMAGES_TXT" ]
  run cat "$IMAGES_TXT"
  [[ "$output" == *"null"* ]]
}

# ── Suite: extract-artifacts ─────────────────────────────

@test "extract-artifacts: happy path processes multiple images" {
  echo "registry.com/image1:latest" > "$IMAGES_TXT"
  echo "registry.com/image2:latest" >> "$IMAGES_TXT"

  run "$SCRIPT_EXTRACT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Processing registry.com/image1:latest"* ]]
  [[ "$output" == *"Processing registry.com/image2:latest"* ]]
  [[ "$output" == *"Extracted files:"* ]]
  [ -f "$FILES_DIR/dummy.txt" ]
  [ -f "$TEST_TEMP_DIR/auth.json" ]
}

@test "extract-artifacts: handles empty images.txt" {
  touch "$IMAGES_TXT"

  run "$SCRIPT_EXTRACT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Processing"* ]]
  [[ "$output" == *"Extracted files:"* ]]
}

@test "extract-artifacts: error when select-oci-auth fails" {
  echo "registry.com/image1:latest" > "$IMAGES_TXT"
  export SELECT_FAIL="true"

  run "$SCRIPT_EXTRACT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Processing registry.com/image1:latest"* ]]
  [[ "$output" == *"select-oci-auth failed"* ]]
}

@test "extract-artifacts: error when oras pull fails" {
  echo "registry.com/image1:latest" > "$IMAGES_TXT"
  export ORAS_FAIL="true"

  run "$SCRIPT_EXTRACT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Processing registry.com/image1:latest"* ]]
  [[ "$output" == *"oras pull failed"* ]]
}

@test "extract-artifacts: error when retry fails" {
  echo "registry.com/image1:latest" > "$IMAGES_TXT"
  export RETRY_FAIL="true"

  run "$SCRIPT_EXTRACT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Processing registry.com/image1:latest"* ]]
  [[ "$output" == *"retry failed"* ]]
}

@test "extract-artifacts: error when images.txt is missing" {
  rm -f "$IMAGES_TXT"

  run "$SCRIPT_EXTRACT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No such file or directory"* ]]
}