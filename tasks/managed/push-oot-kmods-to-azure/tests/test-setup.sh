set -x

echo "Setting up test data for push-oot-kmods task..."

echo "Creating dummy signed kmods and envfile in dataDir..."
mkdir -p "$(params.dataDir)/$(params.signedKmodsPath)/"
echo "AZURE_SIGNED_MODULE1" > "$(params.dataDir)/$(params.signedKmodsPath)/mod1.ko"
echo "AZURE_SIGNED_MODULE2" > "$(params.dataDir)/$(params.signedKmodsPath)/mod2.ko"

cat > "$(params.dataDir)/$(params.signedKmodsPath)/envfile" << EOF
DRIVER_VENDOR="mocked-vendor-azure"
DRIVER_VERSION="1.2.3-az"
KERNEL_VERSION="6.5.0-az"
EOF

echo "Test data setup complete:"
ls -la "$(params.dataDir)/$(params.signedKmodsPath)"