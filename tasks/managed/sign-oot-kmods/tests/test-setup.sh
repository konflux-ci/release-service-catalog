#!/usr/bin/env bash
set -x

# INJECTED TEST SETUP - Create test data for signing task
echo "Setting up test data for sign-oot-kmods task..."

# Create the signed kmods directory and dummy modules in dataDir for trusted artifacts mode
echo "Creating dummy kmods to be signed in dataDir..."
mkdir -p "$(params.dataDir)/$(params.signedKmodsPath)/"
echo "MODULE1" > "$(params.dataDir)/$(params.signedKmodsPath)/mod1.ko"
echo "MODULE2" > "$(params.dataDir)/$(params.signedKmodsPath)/mod2.ko"

echo "Test data setup complete:"
echo "DataDir contents:"
ls -la "$(params.dataDir)" || echo "dataDir does not exist"
if [ -d "$(params.dataDir)/$(params.signedKmodsPath)" ]; then
    ls -la "$(params.dataDir)/$(params.signedKmodsPath)"
fi

# ORIGINAL TASK LOGIC STARTS HERE 
