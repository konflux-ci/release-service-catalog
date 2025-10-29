set -x

echo "Setting up test data for push-oot-kmods-s3 task..."

echo "Creating dummy signed kmods and envfile in dataDir..."
mkdir -p "$(params.dataDir)/$(params.signedKmodsPath)/"
echo "S3_MODULE1" > "$(params.dataDir)/$(params.signedKmodsPath)/mod1.ko"
echo "S3_MODULE2" > "$(params.dataDir)/$(params.signedKmodsPath)/mod2.ko"

cat > "$(params.dataDir)/$(params.signedKmodsPath)/envfile" << EOF
DRIVER_VENDOR="mocked-vendor-s3"
DRIVER_VERSION="1.2.3-s3"
KERNEL_VERSION="6.5.0-s3"
EOF

echo "Test data setup complete:"
ls -la "$(params.dataDir)/$(params.signedKmodsPath)"