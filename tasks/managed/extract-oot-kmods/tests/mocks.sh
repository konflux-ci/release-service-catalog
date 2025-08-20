#!/usr/bin/env bash
set -eux

# Create the snapshot.json file that the task expects to read
echo "Creating snapshot.json file for task to read..."
mkdir -p "$(params.dataDir)"
cat > "$(params.dataDir)/snapshot.json" << 'EOF'
{
  "components": [
    {
      "containerImage": "quay.io/mock/image@sha256:dummy"
    }
  ]
}
EOF

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

skopeo() {
  echo "Mock skopeo called with: $*"
  # Write to workspace since the task runs there initially
  echo "$*" >> "$(params.dataDir)/mock_skopeo.txt"

  case "$*" in
    "copy docker://quay.io/mock/image@sha256:dummy dir:"*)
      # Create a proper manifest.json with layers
      cat > "$tmp_dir/manifest.json" << 'EOF'
{
  "layers": [
    {"digest": "sha256:mocklayer123"}
  ]
}
EOF
      
      # Create a temporary directory to build the tar structure
      LAYER_BUILD_DIR=$(mktemp -d)
      
      # Create the kmods directory structure
      mkdir -p "$LAYER_BUILD_DIR/kmods"
      
      echo "mock-kmod1" > "$LAYER_BUILD_DIR/kmods/mod1.ko"
      echo "mock-kmod2" > "$LAYER_BUILD_DIR/kmods/mod2.ko"
      
      # The task expects envfile at $TMP_DIR$KMODS_PATH/../../envfile
      # For kmodsPath=/kmods, this resolves to $TMP_DIR/envfile
      # So we need to put envfile at the root of the layer structure
      echo "DRIVER_VERSION=1.0.0" > "$LAYER_BUILD_DIR/envfile"
      echo "DRIVER_VENDOR=test-vendor" >> "$LAYER_BUILD_DIR/envfile"
      echo "KERNEL_VERSION=5.4.0" >> "$LAYER_BUILD_DIR/envfile"
      
      # Create the layer tar file with the complete structure
      (cd "$LAYER_BUILD_DIR" && tar -cf "$tmp_dir/mocklayer123" .)
      
      # Clean up the temporary build directory
      rm -rf "$LAYER_BUILD_DIR"
      
      # Debug: Let's see what we actually created
      echo "Debug: Contents of tmp_dir after tar creation:"
      ls -la "$tmp_dir/"
      ;;
    *)
      echo "Error: Unexpected skopeo call: $*"
      exit 1
      ;;
  esac
}
