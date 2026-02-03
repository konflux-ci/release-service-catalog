#!/usr/bin/env bash
set -x

# INJECTED TEST SETUP - Create test data for signing task
echo "Setting up test data for sign-oot-kmods task..."

# Ensure dataDir exists
mkdir -p "$(params.dataDir)"

# Create arch_count.txt to indicate single-arch build with subdirectory structure
# This triggers the new single-arch subdirectory logic instead of the fallback
echo "1" > "$(params.dataDir)/arch_count.txt"

# Create the signed kmods directory with recursive architecture subdirectory structure
# This matches the extract task output which creates recursive directory structures
echo "Creating dummy kmods to be signed in dataDir with recursive architecture subdirectory structure..."
ARCH_SUBDIR="x86_64"
mkdir -p "$(params.dataDir)/$(params.signedKmodsPath)/${ARCH_SUBDIR}"
mkdir -p "$(params.dataDir)/$(params.signedKmodsPath)/${ARCH_SUBDIR}/driversA"
mkdir -p "$(params.dataDir)/$(params.signedKmodsPath)/${ARCH_SUBDIR}/driversB"
mkdir -p "$(params.dataDir)/$(params.signedKmodsPath)/${ARCH_SUBDIR}/driversB/submodule"

# Create .ko files in top-level and subdirectories to test recursive signing
echo "MODULE1" > "$(params.dataDir)/$(params.signedKmodsPath)/${ARCH_SUBDIR}/mod1.ko"
echo "MODULE2" > "$(params.dataDir)/$(params.signedKmodsPath)/${ARCH_SUBDIR}/mod2.ko"
echo "DRIVER_A_MODULE1" > "$(params.dataDir)/$(params.signedKmodsPath)/${ARCH_SUBDIR}/driversA/driverA-mod1.ko"
echo "DRIVER_A_MODULE2" > "$(params.dataDir)/$(params.signedKmodsPath)/${ARCH_SUBDIR}/driversA/driverA-mod2.ko"
echo "DRIVER_B_MODULE1" > "$(params.dataDir)/$(params.signedKmodsPath)/${ARCH_SUBDIR}/driversB/driverB-mod1.ko"
echo "DRIVER_B_SUBMODULE" > "$(params.dataDir)/$(params.signedKmodsPath)/${ARCH_SUBDIR}/driversB/submodule/submodule.ko"

echo "Test data setup complete:"
echo "DataDir contents:"
ls -la "$(params.dataDir)" || echo "dataDir does not exist"
if [ -d "$(params.dataDir)/$(params.signedKmodsPath)" ]; then
    ls -la "$(params.dataDir)/$(params.signedKmodsPath)"
    ls -la "$(params.dataDir)/$(params.signedKmodsPath)/${ARCH_SUBDIR}"
fi

# ORIGINAL TASK LOGIC STARTS HERE 
