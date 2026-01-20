set -x

echo "Setting up test data for push-oot-kmods-s3 task..."

echo "Creating dummy signed kmods and envfile in dataDir with arch-specific structure..."
# Create architecture-specific directory structure
mkdir -p "$(params.dataDir)/$(params.signedKmodsPath)/x86_64"
echo "S3_MODULE1" > "$(params.dataDir)/$(params.signedKmodsPath)/x86_64/mod1.ko"
echo "S3_MODULE2" > "$(params.dataDir)/$(params.signedKmodsPath)/x86_64/mod2.ko"

# IMPORTANT: KERNEL_VERSION includes .x86_64 architecture suffix
# This tests that the task properly strips the suffix when constructing upload paths
# Expected: task strips .x86_64 to produce path mocked-vendor-s3/1.2.3-s3/6.5.0-s3/x86_64/
# NOT: mocked-vendor-s3/1.2.3-s3/6.5.0-s3.x86_64/x86_64/
cat > "$(params.dataDir)/$(params.signedKmodsPath)/x86_64/envfile" << EOF
DRIVER_VENDOR="mocked-vendor-s3"
DRIVER_VERSION="1.2.3-s3"
KERNEL_VERSION="6.5.0-s3.x86_64"
EOF

# Create architecture-specific checksum file
cat > "$(params.dataDir)/$(params.signedKmodsPath)/x86_64/signed_kmods_checksums_x86_64.txt" << EOF
$(sha256sum "$(params.dataDir)/$(params.signedKmodsPath)/x86_64/mod1.ko" | awk '{print $1}')  mod1.ko
$(sha256sum "$(params.dataDir)/$(params.signedKmodsPath)/x86_64/mod2.ko" | awk '{print $1}')  mod2.ko
EOF

echo "Test data setup complete:"
ls -la "$(params.dataDir)/$(params.signedKmodsPath)/x86_64"