#!/bin/bash
set -euo pipefail

# Script to sign all images in the image pool with test cosign key
# This enables full Enterprise Contract validation with STRICT: true
#
# Usage: ./sign-image-pool.sh [image-pool-file] [cosign-key]
#
# Prerequisites:
#   - cosign CLI tool installed
#   - Registry write permissions (push-${component_name} secret)
#   - Cosign private key (from vault or local file)

IMAGE_POOL_FILE="${1:-/tmp/image-pool-200.txt}"
COSIGN_KEY="${2:-cosign.key}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}🔐 Signing Image Pool for EC Validation${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check prerequisites
if [ ! -f "${IMAGE_POOL_FILE}" ]; then
    echo -e "${RED}ERROR: Image pool file not found: ${IMAGE_POOL_FILE}${NC}"
    echo "Generate it first with:"
    echo "  ./generate-image-pool.sh 200 ${IMAGE_POOL_FILE}"
    exit 1
fi

if ! command -v cosign &> /dev/null; then
    echo -e "${RED}ERROR: cosign CLI not found${NC}"
    echo "Install it from: https://github.com/sigstore/cosign"
    exit 1
fi

if [ ! -f "${COSIGN_KEY}" ]; then
    echo -e "${YELLOW}WARNING: Cosign key not found at: ${COSIGN_KEY}${NC}"
    echo ""
    echo "To extract the key from vault:"
    echo "  1. Decrypt vault: ansible-vault decrypt integration-tests/rh-advisories-large-snapshot/vault/managed-secrets.yaml"
    echo "  2. Extract cosign.key from the konflux-cosign-signing-stage secret"
    echo "  3. Save to ${COSIGN_KEY}"
    echo ""
    read -p "Do you want to use a different key path? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Enter key path: " COSIGN_KEY
        if [ ! -f "${COSIGN_KEY}" ]; then
            echo -e "${RED}ERROR: Key not found: ${COSIGN_KEY}${NC}"
            exit 1
        fi
    else
        exit 1
    fi
fi

# Count images
TOTAL_IMAGES=$(wc -l < "${IMAGE_POOL_FILE}")

echo "Configuration:"
echo "  📝 Image pool: ${IMAGE_POOL_FILE}"
echo "  🔑 Signing key: ${COSIGN_KEY}"
echo "  📊 Total images: ${TOTAL_IMAGES}"
echo ""

read -p "Continue with signing? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Signing logic
SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

START_TIME=$(date +%s)

echo ""
echo -e "${YELLOW}🔐 Signing images...${NC}"
echo ""

while IFS= read -r image || [ -n "$image" ]; do
    # Skip empty lines
    [ -z "$image" ] && continue
    
    IMAGE_NUM=$((SUCCESS_COUNT + FAIL_COUNT + SKIP_COUNT + 1))
    
    echo -n "[${IMAGE_NUM}/${TOTAL_IMAGES}] ${image} ... "
    
    # Check if already signed
    if cosign verify --key "${COSIGN_KEY}.pub" "$image" &>/dev/null 2>&1; then
        echo -e "${YELLOW}already signed, skipping${NC}"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi
    
    # Sign the image
    if cosign sign --yes --key "${COSIGN_KEY}" "$image" &>/dev/null; then
        echo -e "${GREEN}✓ signed${NC}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "${RED}✗ failed${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    
    # Progress update every 20 images
    if [ $((IMAGE_NUM % 20)) -eq 0 ]; then
        ELAPSED=$(($(date +%s) - START_TIME))
        RATE=$((IMAGE_NUM / (ELAPSED + 1)))
        REMAINING=$((TOTAL_IMAGES - IMAGE_NUM))
        ETA=$((REMAINING / (RATE + 1)))
        echo ""
        echo "   Progress: ${IMAGE_NUM}/${TOTAL_IMAGES} | Rate: ~${RATE} img/s | ETA: ~${ETA}s"
        echo ""
    fi
done < "${IMAGE_POOL_FILE}"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}📊 Signing Complete${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Statistics:"
echo "  ⏱️  Time elapsed: ${MINUTES}m ${SECONDS}s"
echo "  ✅ Successfully signed: ${SUCCESS_COUNT}"
echo "  ⊘ Already signed (skipped): ${SKIP_COUNT}"
echo "  ✗ Failed: ${FAIL_COUNT}"
echo "  📝 Total processed: $((SUCCESS_COUNT + FAIL_COUNT + SKIP_COUNT))"
echo ""

if [ ${FAIL_COUNT} -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Warning: ${FAIL_COUNT} images failed to sign${NC}"
    echo "   Check registry permissions and network connectivity"
    echo ""
fi

if [ ${SUCCESS_COUNT} -gt 0 ] || [ ${SKIP_COUNT} -gt 0 ]; then
    echo -e "${GREEN}✅ Images are now signed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Verify a signature:"
    echo "     cosign verify --key ${COSIGN_KEY}.pub <image@digest>"
    echo ""
    echo "  2. Update pipeline configuration:"
    echo "     - Set STRICT: \"true\" in verify-conforma task"
    echo "     - Set conformaPubKey to point to your secret"
    echo ""
    echo "  3. Run the test with full EC validation enabled!"
    echo ""
else
    echo -e "${RED}❌ No images were signed${NC}"
    exit 1
fi
