#!/usr/bin/env bash
set -euo pipefail

# Create the single-arch tree the signing step reads from the shared workspace.
echo "Setting up test data for sign-oot-kmods task..."

mkdir -p "$(params.dataDir)"

ARCH_SUBDIR="x86_64"
BASE="$(params.dataDir)/$(params.signedKmodsPath)/${ARCH_SUBDIR}"
mkdir -p "${BASE}"

echo "MODULE1" > "${BASE}/mod1.ko"
echo "MODULE2" > "${BASE}/mod2.ko"
