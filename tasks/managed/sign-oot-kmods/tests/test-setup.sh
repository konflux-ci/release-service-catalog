#!/usr/bin/env bash
set -x

# INJECTED TEST SETUP - Create test data for signing task
echo "Setting up test data for sign-oot-kmods task..."

# Ensure dataDir exists
mkdir -p "$(params.dataDir)"

# Create arch_count.txt to indicate single-arch build with subdirectory structure
# This triggers the new single-arch subdirectory logic instead of the fallback
echo "1" > "$(params.dataDir)/arch_count.txt"

# Create the signed kmods directory with architecture subdirectory structure
# This matches the extract task output which always creates an arch subdirectory
echo "Creating dummy kmods to be signed in dataDir with architecture subdirectory..."
ARCH_SUBDIR="x86_64"
mkdir -p "$(params.dataDir)/$(params.signedKmodsPath)/${ARCH_SUBDIR}"
echo "MODULE1" > "$(params.dataDir)/$(params.signedKmodsPath)/${ARCH_SUBDIR}/mod1.ko"
echo "MODULE2" > "$(params.dataDir)/$(params.signedKmodsPath)/${ARCH_SUBDIR}/mod2.ko"

echo "Test data setup complete:"
echo "DataDir contents:"
ls -la "$(params.dataDir)" || echo "dataDir does not exist"
if [ -d "$(params.dataDir)/$(params.signedKmodsPath)" ]; then
    ls -la "$(params.dataDir)/$(params.signedKmodsPath)"
    ls -la "$(params.dataDir)/$(params.signedKmodsPath)/${ARCH_SUBDIR}"
fi

# ORIGINAL TASK LOGIC STARTS HERE 
