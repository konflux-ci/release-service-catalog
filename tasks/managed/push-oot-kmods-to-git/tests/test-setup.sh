#!/usr/bin/env bash
set -x

echo "Setting up test data for push-oot-kmods-to-git task..."

KMODS_DIR="$(params.dataDir)/$(params.signedKmodsPath)"

# Create arch_count.txt to indicate single-arch build with subdirectory structure
echo "1" > "$(params.dataDir)/arch_count.txt"

echo "Creating dummy signed kmods in dataDir with recursive architecture subdirectory structure..."
ARCH_DIR="$KMODS_DIR/x86_64"
mkdir -p "$ARCH_DIR"
mkdir -p "$ARCH_DIR/driversA"
mkdir -p "$ARCH_DIR/driversB"

# Create .ko files in top-level and subdirectories to test recursive push
echo "SIGNED_MODULE1_CONTENT" > "$ARCH_DIR/mod1.ko"
echo "SIGNED_MODULE2_CONTENT" > "$ARCH_DIR/mod2.ko"
echo "SIGNED_DRIVER_A_MODULE1" > "$ARCH_DIR/driversA/driverA-mod1.ko"
echo "SIGNED_DRIVER_A_MODULE2" > "$ARCH_DIR/driversA/driverA-mod2.ko"
echo "SIGNED_DRIVER_B_MODULE1" > "$ARCH_DIR/driversB/driverB-mod1.ko"

echo "Creating valid checksum file..."
(
  cd "$ARCH_DIR" || exit
  sha256sum mod1.ko mod2.ko driversA/driverA-mod1.ko driversA/driverA-mod2.ko driversB/driverB-mod1.ko > signed_kmods_checksums_x86_64.txt
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
echo "Architecture directory structure:"
find "$ARCH_DIR" -type f | sort
echo "Tarball created:"
ls -la "$(params.dataDir)/signed-kmods.tar.gz"
echo "Tarball contents:"
tar -tzf "$(params.dataDir)/signed-kmods.tar.gz" | head -5