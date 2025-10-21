#!/usr/bin/env bash
set -x

# INJECTED TEST SETUP - Create test data for push-oot-kmods task
echo "Setting up test data for push-oot-kmods task..."

# Create the signed kmods directory and dummy modules in dataDir for trusted artifacts mode
echo "Creating dummy signed kmods and envfile in dataDir..."
mkdir -p "$(params.dataDir)/$(params.signedKmodsPath)/"
echo "SIGNED_MODULE1" > "$(params.dataDir)/$(params.signedKmodsPath)/mod1.ko"
echo "SIGNED_MODULE2" > "$(params.dataDir)/$(params.signedKmodsPath)/mod2.ko"

# Create envfile with mock environment variables
cat > "$(params.dataDir)/$(params.signedKmodsPath)/envfile" << EOF
DRIVER_VENDOR="$(params.vendor)"
DRIVER_VERSION="1.0.0"
KERNEL_VERSION="5.14.0"
EOF

# Also create mocked-envfile for the check-result task (won't be removed by main script)
cat > "$(params.dataDir)/$(params.signedKmodsPath)/mocked-envfile" << EOF
DRIVER_VENDOR="$(params.vendor)"
DRIVER_VERSION="1.0.0"
KERNEL_VERSION="5.14.0"
EOF

# Generate checksums file to match sign-oot-kmods task output
cd "$(params.dataDir)/$(params.signedKmodsPath)/"
sha256sum *.ko > signed_kmods_checksums.txt
echo "Generated checksums file for test .ko files"

echo "Test data setup complete:"
echo "DataDir contents:"
ls -la "$(params.dataDir)" || echo "dataDir does not exist"
if [ -d "$(params.dataDir)/$(params.signedKmodsPath)" ]; then
    ls -la "$(params.dataDir)/$(params.signedKmodsPath)"
fi

# ORIGINAL TASK LOGIC STARTS HERE
