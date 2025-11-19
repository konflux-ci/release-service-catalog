#!/usr/bin/env bash
set -eux

echo "=== MOCK SETUP: Starting extract-oot-kmods mocks ==="

# Create the snapshot.json file that the task expects to read
echo "Creating snapshot.json file for test..."
mkdir -p "$(params.dataDir)"

# Always create a default snapshot.json - the get-image-architectures mock will handle multiarch detection
echo "Creating default snapshot.json file..."
cat > "$(params.dataDir)/snapshot.json" << 'EOF'
{
  "components": [
    {
      "containerImage": "quay.io/mock/image@sha256:dummy"
    }
  ]
}
EOF
echo "Created snapshot.json with mock image reference"

# Mock `get-resource` for testing - must return a proper snapshot object
function get-resource() {
   case "$1" in
     "snapshot")
       echo '{
         "components": [
           {
             "containerImage": "quay.io/mock/image@sha256:dummy"
           }
         ]
       }'
       ;;
     *)
       echo "Mock get-resource called for unsupported resource: $1" >&2
       exit 1
       ;;
   esac
}

# Export the function so it's available in the script environment
export -f get-resource

# Mock get-image-architectures function for multi-arch testing
get-image-architectures() {
  echo "Mock get-image-architectures called with: $*" >&2
  local image="$1"

  # Check if this appears to be a multiarch test based on the snapshot parameter or environment
  if [[ "${EXPECT_MULTIARCH:-}" == "true" ]] || \
     [[ "${SNAPSHOT_NAME:-}" == *"multiarch"* ]] || \
     [[ "$image" == *"multiarch"* ]]; then
    # Return multi-architecture response for multiarch test images
    echo '{
      "platform": {"architecture": "amd64", "os": "linux"},
      "digest": "sha256:amd64digest123",
      "multiarch": true
    }'
    echo '{
      "platform": {"architecture": "arm64", "os": "linux"},
      "digest": "sha256:arm64digest456",
      "multiarch": true
    }'
  else
    # Return single architecture response for regular test images
    echo '{
      "platform": {"architecture": "amd64", "os": "linux"},
      "digest": "sha256:singlearchtdigest789",
      "multiarch": false
    }'
  fi
}

# Export the get-image-architectures function so it's available to the task script
export -f get-image-architectures

skopeo() {
  echo "Mock skopeo called with: $*"
  # Write to workspace since the task runs there initially
  echo "$*" >> "$(params.dataDir)/mock_skopeo.txt"

  case "$*" in
    "copy docker://quay.io/mock/image@sha256:dummy dir:"*)
      # Create a proper manifest.json with layers for single arch
      cat > "$tmp_dir/manifest.json" << 'EOF'
{
  "layers": [
    {"digest": "sha256:mocklayer123"}
  ]
}
EOF

      # Create a temporary directory to build the tar structure
      LAYER_BUILD_DIR=$(mktemp -d)

      # Create the kmods directory structure with leading slash to match task expectation
      # Task looks for "^${KMODS_PATH#/}/" where KMODS_PATH=/kmods, so it looks for "^kmods/"
      mkdir -p "$LAYER_BUILD_DIR/kmods"

      echo "mock-kmod1" > "$LAYER_BUILD_DIR/kmods/mod1.ko"
      echo "mock-kmod2" > "$LAYER_BUILD_DIR/kmods/mod2.ko"

      # The task expects envfile at $TMP_DIR$KMODS_PATH/../../envfile
      # For kmodsPath=/kmods, this resolves to $TMP_DIR/envfile
      # So we need to put envfile at the root of the layer structure
      echo "DRIVER_VERSION=1.0.0" > "$LAYER_BUILD_DIR/envfile"
      echo "DRIVER_VENDOR=test-vendor" >> "$LAYER_BUILD_DIR/envfile"
      echo "KERNEL_VERSION=5.4.0" >> "$LAYER_BUILD_DIR/envfile"

      # Create the layer tar file with mixed entry formats for task compatibility
      # The task expects "kmods/" entries (without ./), but "./envfile" entries (with ./)
      (cd "$LAYER_BUILD_DIR" && tar -cf "$tmp_dir/mocklayer123" --transform 's,^\./kmods/,kmods/,' .)

      # Clean up the temporary build directory
      rm -rf "$LAYER_BUILD_DIR"

      # Debug: Let's see what we actually created
      echo "Debug: Contents of tmp_dir after tar creation:"
      ls -la "$tmp_dir/"
      ;;
    "copy docker://quay.io/mock/multiarch@sha256:amd64digest123 dir:"*)
      # Create manifest for amd64 architecture
      cat > "$tmp_dir/manifest.json" << 'EOF'
{
  "layers": [
    {"digest": "sha256:amd64layer123"}
  ]
}
EOF

      LAYER_BUILD_DIR=$(mktemp -d)
      mkdir -p "$LAYER_BUILD_DIR/kmods"

      echo "amd64-kmod1" > "$LAYER_BUILD_DIR/kmods/amd64-mod1.ko"
      echo "amd64-kmod2" > "$LAYER_BUILD_DIR/kmods/amd64-mod2.ko"
      echo "DRIVER_VERSION=1.0.0" > "$LAYER_BUILD_DIR/envfile"
      echo "DRIVER_VENDOR=test-vendor" >> "$LAYER_BUILD_DIR/envfile"
      echo "KERNEL_VERSION=5.4.0" >> "$LAYER_BUILD_DIR/envfile"

      (cd "$LAYER_BUILD_DIR" && tar -cf "$tmp_dir/amd64layer123" --transform 's,^\./kmods/,kmods/,' .)
      rm -rf "$LAYER_BUILD_DIR"
      ;;
    "copy docker://quay.io/mock/multiarch@sha256:arm64digest456 dir:"*)
      # Create manifest for arm64 architecture
      cat > "$tmp_dir/manifest.json" << 'EOF'
{
  "layers": [
    {"digest": "sha256:arm64layer456"}
  ]
}
EOF

      LAYER_BUILD_DIR=$(mktemp -d)
      mkdir -p "$LAYER_BUILD_DIR/kmods"

      echo "arm64-kmod1" > "$LAYER_BUILD_DIR/kmods/arm64-mod1.ko"
      echo "arm64-kmod2" > "$LAYER_BUILD_DIR/kmods/arm64-mod2.ko"
      echo "DRIVER_VERSION=1.0.0" > "$LAYER_BUILD_DIR/envfile"
      echo "DRIVER_VENDOR=test-vendor" >> "$LAYER_BUILD_DIR/envfile"
      echo "KERNEL_VERSION=5.4.0" >> "$LAYER_BUILD_DIR/envfile"

      (cd "$LAYER_BUILD_DIR" && tar -cf "$tmp_dir/arm64layer456" --transform 's,^\./kmods/,kmods/,' .)
      rm -rf "$LAYER_BUILD_DIR"
      ;;
    "copy docker://quay.io/mock/multiarch@sha256:multiarchdigest dir:"*)
      # This is the initial image inspection - should not create files
      # The task will call get-image-architectures which will return multiple archs
      # Then it will call skopeo for each architecture-specific digest
      echo "Multiarch image inspection - no files created here"
      ;;
    "copy docker://quay.io/mock/multiarch@"*"amd64digest123 dir:"*)
      # Create manifest for amd64 architecture (alternative digest format)
      cat > "$tmp_dir/manifest.json" << 'EOF'
{
  "layers": [
    {"digest": "sha256:amd64layer123"}
  ]
}
EOF

      LAYER_BUILD_DIR=$(mktemp -d)
      mkdir -p "$LAYER_BUILD_DIR/kmods"

      echo "amd64-kmod1" > "$LAYER_BUILD_DIR/kmods/amd64-mod1.ko"
      echo "amd64-kmod2" > "$LAYER_BUILD_DIR/kmods/amd64-mod2.ko"
      echo "DRIVER_VERSION=1.0.0" > "$LAYER_BUILD_DIR/envfile"
      echo "DRIVER_VENDOR=test-vendor" >> "$LAYER_BUILD_DIR/envfile"
      echo "KERNEL_VERSION=5.4.0" >> "$LAYER_BUILD_DIR/envfile"

      (cd "$LAYER_BUILD_DIR" && tar -cf "$tmp_dir/amd64layer123" --transform 's,^\./kmods/,kmods/,' .)
      rm -rf "$LAYER_BUILD_DIR"
      ;;
    "copy docker://quay.io/mock/multiarch@"*"arm64digest456 dir:"*)
      # Create manifest for arm64 architecture (alternative digest format)
      cat > "$tmp_dir/manifest.json" << 'EOF'
{
  "layers": [
    {"digest": "sha256:arm64layer456"}
  ]
}
EOF

      LAYER_BUILD_DIR=$(mktemp -d)
      mkdir -p "$LAYER_BUILD_DIR/kmods"

      echo "arm64-kmod1" > "$LAYER_BUILD_DIR/kmods/arm64-mod1.ko"
      echo "arm64-kmod2" > "$LAYER_BUILD_DIR/kmods/arm64-mod2.ko"
      echo "DRIVER_VERSION=1.0.0" > "$LAYER_BUILD_DIR/envfile"
      echo "DRIVER_VENDOR=test-vendor" >> "$LAYER_BUILD_DIR/envfile"
      echo "KERNEL_VERSION=5.4.0" >> "$LAYER_BUILD_DIR/envfile"

      (cd "$LAYER_BUILD_DIR" && tar -cf "$tmp_dir/arm64layer456" --transform 's,^\./kmods/,kmods/,' .)
      rm -rf "$LAYER_BUILD_DIR"
      ;;
    *"@sha256:dummy@sha256:amd64digest123"*)
      # Handle double digest case for amd64 multiarch
      cat > "$tmp_dir/manifest.json" << 'EOF'
{
  "layers": [
    {"digest": "sha256:amd64layer123"}
  ]
}
EOF

      LAYER_BUILD_DIR=$(mktemp -d)
      mkdir -p "$LAYER_BUILD_DIR/kmods"

      echo "amd64-kmod1" > "$LAYER_BUILD_DIR/kmods/amd64-mod1.ko"
      echo "amd64-kmod2" > "$LAYER_BUILD_DIR/kmods/amd64-mod2.ko"
      echo "DRIVER_VERSION=1.0.0" > "$LAYER_BUILD_DIR/envfile"
      echo "DRIVER_VENDOR=test-vendor" >> "$LAYER_BUILD_DIR/envfile"
      echo "KERNEL_VERSION=5.4.0" >> "$LAYER_BUILD_DIR/envfile"

      (cd "$LAYER_BUILD_DIR" && tar -cf "$tmp_dir/amd64layer123" --transform 's,^\./kmods/,kmods/,' .)
      rm -rf "$LAYER_BUILD_DIR"
      ;;
    *"@sha256:dummy@sha256:arm64digest456"*)
      # Handle double digest case for arm64 multiarch
      cat > "$tmp_dir/manifest.json" << 'EOF'
{
  "layers": [
    {"digest": "sha256:arm64layer456"}
  ]
}
EOF

      LAYER_BUILD_DIR=$(mktemp -d)
      mkdir -p "$LAYER_BUILD_DIR/kmods"

      echo "arm64-kmod1" > "$LAYER_BUILD_DIR/kmods/arm64-mod1.ko"
      echo "arm64-kmod2" > "$LAYER_BUILD_DIR/kmods/arm64-mod2.ko"
      echo "DRIVER_VERSION=1.0.0" > "$LAYER_BUILD_DIR/envfile"
      echo "DRIVER_VENDOR=test-vendor" >> "$LAYER_BUILD_DIR/envfile"
      echo "KERNEL_VERSION=5.4.0" >> "$LAYER_BUILD_DIR/envfile"

      (cd "$LAYER_BUILD_DIR" && tar -cf "$tmp_dir/arm64layer456" --transform 's,^\./kmods/,kmods/,' .)
      rm -rf "$LAYER_BUILD_DIR"
      ;;
    *)
      echo "Error: Unexpected skopeo call: $*"
      exit 1
      ;;
  esac
}

# Export the skopeo function so it's available to the task script
export -f skopeo

echo "=== MOCK SETUP: All mocks configured and exported ==="
echo "Available mock functions:"
echo "- get-resource (for snapshot lookups)"
echo "- get-image-architectures (for architecture detection)"
echo "- skopeo (for image copying operations)"
echo "==="
