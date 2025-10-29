set -x

echo "Setting up test data for push-oot-kmods-to-git task..."

KMODS_DIR="$(params.dataDir)/$(params.signedKmodsPath)"

echo "Creating dummy signed kmods in dataDir..."
mkdir -p "$KMODS_DIR"
echo "SIGNED_MODULE1_CONTENT" > "$KMODS_DIR/mod1.ko"
echo "SIGNED_MODULE2_CONTENT" > "$KMODS_DIR/mod2.ko"

echo "Creating valid checksum file..."
(
  cd "$KMODS_DIR"
  sha256sum mod1.ko mod2.ko > signed_kmods_checksums.txt
)

echo "Creating envfile..."
cat > "$KMODS_DIR/envfile" << EOF
DRIVER_VENDOR="mocked-vendor"
DRIVER_VERSION="1.2.3"
KERNEL_VERSION="6.5.0"
EOF

echo "Test data setup complete:"
ls -la "$KMODS_DIR"