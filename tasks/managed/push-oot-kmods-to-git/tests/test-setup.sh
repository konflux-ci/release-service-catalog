#!/usr/bin/env bash
set -x

echo "Setting up test data for push-oot-kmods-to-git task..."

KMODS_DIR="$(params.dataDir)/$(params.signedKmodsPath)"

# Create arch_count.txt to indicate single-arch build with subdirectory structure
echo "1" > "$(params.dataDir)/arch_count.txt"

echo "Creating dummy signed kmods in dataDir with recursive architecture subdirectory structure..."
# Create architecture-specific directory structure with large-scale nested subdirectories
# This tests the SIGPIPE bug fix which only occurs with 100+ directories
ARCH_DIR="$KMODS_DIR/x86_64"
mkdir -p "$ARCH_DIR"

echo "Creating large-scale directory structure (110 dirs) to test SIGPIPE fix..."
# Create top-level modules
echo "SIGNED_MODULE1_CONTENT" > "$ARCH_DIR/mod1.ko"
echo "SIGNED_MODULE2_CONTENT" > "$ARCH_DIR/mod2.ko"

# Create 110 driver directories with nested structure (similar to Jetson case)
for i in $(seq 1 110); do
  driver_dir="$ARCH_DIR/driver_$(printf "%03d" $i)"
  mkdir -p "$driver_dir/subdir_a/subdir_b"
  echo "SIGNED_DRIVER_${i}_MODULE" > "$driver_dir/mod_${i}.ko"

  # Some drivers have nested modules
  if [ $((i % 10)) -eq 0 ]; then
    echo "SIGNED_DRIVER_${i}_NESTED" > "$driver_dir/subdir_a/subdir_b/nested_mod_${i}.ko"
  fi
done

echo "Created $(find "$ARCH_DIR" -name "*.ko" | wc -l) .ko files in $(find "$ARCH_DIR" -type d | wc -l) directories"

echo "Creating valid checksum file for all .ko files..."
(
  cd "$ARCH_DIR" || exit
  find . -name "*.ko" -type f -exec sha256sum {} \; | sed 's|^\([^ ]*\)  \./|\1  |' | sort -k2 > signed_kmods_checksums_x86_64.txt
  echo "Generated checksums for $(wc -l < signed_kmods_checksums_x86_64.txt) files"
)

echo "Creating envfile in architecture directory..."
# IMPORTANT: KERNEL_VERSION includes .x86_64 architecture suffix
# This tests that the task properly strips the suffix when constructing upload paths
# Expected: task strips .x86_64 to produce path mocked-vendor/1.2.3/6.5.0/
# NOT: mocked-vendor/1.2.3/6.5.0.x86_64/
cat > "$ARCH_DIR/envfile" << EOF
DRIVER_VENDOR="mocked-vendor"
DRIVER_VERSION="1.2.3"
KERNEL_VERSION="6.5.0.x86_64"
EOF

# Create signed-kmods.tar.gz file to simulate what sign-oot-kmods produces
echo "Creating signed-kmods.tar.gz to simulate signing task output..."
cd "$(params.dataDir)"
tar -czf signed-kmods.tar.gz "$(params.signedKmodsPath)"

echo "Test data setup complete:"
ls -la "$KMODS_DIR"
echo "Architecture directory structure (showing first 10 files):"
find "$ARCH_DIR" -type f | sort | head -10
echo "... and $(find "$ARCH_DIR" -type f | wc -l) total files"
echo "Tarball created:"
ls -la "$(params.dataDir)/signed-kmods.tar.gz"
echo "Tarball contents (showing first 10 entries):"
tar -tzf "$(params.dataDir)/signed-kmods.tar.gz" | head -10
echo "... (tarball contains $(tar -tzf "$(params.dataDir)/signed-kmods.tar.gz" | wc -l) total entries)"