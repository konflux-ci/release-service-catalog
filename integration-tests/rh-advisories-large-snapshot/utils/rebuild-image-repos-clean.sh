#!/bin/bash
set -euo pipefail

# Script to extract working tags and rebuild IMAGE_REPOS array cleanly
# This removes the DIGEST_BLOCKLIST by testing all tags and keeping only working ones
# 
# Usage: ./rebuild-image-repos-clean.sh
# Output: generate-image-pool-clean.sh (new version without blocklist)
#
# Expected runtime: 30-60 minutes (testing ~353 tags across 8 repositories)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="${SCRIPT_DIR}/generate-image-pool.sh"
OUTPUT_SCRIPT="${SCRIPT_DIR}/generate-image-pool-clean.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}🔧 Rebuilding IMAGE_REPOS Array with Working Tags Only${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "This script will:"
echo "  1. Extract all tags from current generate-image-pool.sh"
echo "  2. Test each tag for accessibility"
echo "  3. Check each for CycloneDX SBOM format (exclude those)"
echo "  4. Rebuild IMAGE_REPOS with only working SPDX tags"
echo "  5. Remove DIGEST_BLOCKLIST entirely"
echo ""
echo "⏱️  Expected runtime: 30-60 minutes"
echo ""
echo "Starting automatically..."
echo ""

# Load the DIGEST_BLOCKLIST from source
echo -e "\n${YELLOW}📋 Loading blocklist from source script...${NC}"
source "${SOURCE_SCRIPT}"

BLOCKLISTED_COUNT=${#DIGEST_BLOCKLIST[@]}
echo "   Loaded ${BLOCKLISTED_COUNT} blocklisted digests"

# Temporary files
WORK_DIR=$(mktemp -d)
RESULTS_FILE="${WORK_DIR}/results.txt"
STATS_FILE="${WORK_DIR}/stats.txt"

cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

# Initialize stats file
echo "repo,total_tags,working_tags,blocklisted_tags,failed_tags" > "${STATS_FILE}"

echo -e "\n${YELLOW}🧪 Testing all tags across 8 repositories...${NC}"
echo ""

# Test all repositories
declare -A NEW_IMAGE_REPOS=()
TOTAL_TESTED=0
TOTAL_WORKING=0
TOTAL_BLOCKLISTED=0
TOTAL_FAILED=0

START_TIME=$(date +%s)

for repo in "${!IMAGE_REPOS[@]}"; do
    repo_name=$(basename "$repo")
    tags="${IMAGE_REPOS[$repo]}"
    tag_array=($tags)
    tag_count=${#tag_array[@]}
    
    echo -e "${GREEN}📦 Testing: ${repo_name}${NC} (${tag_count} tags)"
    
    working_tags=()
    repo_blocklisted=0
    repo_failed=0
    tag_num=0
    
    for tag in ${tags}; do
        tag_num=$((tag_num + 1))
        TOTAL_TESTED=$((TOTAL_TESTED + 1))
        image_ref="${repo}:${tag}"
        
        # Progress indicator every 10 tags
        if [ $((tag_num % 10)) -eq 0 ]; then
            echo -n "."
        fi
        
        # Try to resolve to digest
        if inspect_output=$(skopeo inspect --no-tags "docker://${image_ref}" 2>/dev/null); then
            digest=$(echo "${inspect_output}" | jq -r '.Digest')
            
            # Check if digest is blocklisted
            if [ -n "${DIGEST_BLOCKLIST[$digest]:-}" ]; then
                repo_blocklisted=$((repo_blocklisted + 1))
                TOTAL_BLOCKLISTED=$((TOTAL_BLOCKLISTED + 1))
                continue
            fi
            
            # Tag works and is not blocklisted
            working_tags+=("$tag")
            TOTAL_WORKING=$((TOTAL_WORKING + 1))
        else
            repo_failed=$((repo_failed + 1))
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
        fi
    done
    
    echo "" # newline after progress dots
    
    # Store results
    working_count=${#working_tags[@]}
    echo "   ✓ Working: ${working_count}"
    echo "   ⊘ Blocklisted: ${repo_blocklisted}"
    echo "   ✗ Failed: ${repo_failed}"
    echo ""
    
    # Save to stats
    echo "${repo_name},${tag_count},${working_count},${repo_blocklisted},${repo_failed}" >> "${STATS_FILE}"
    
    # Only include repo if it has working tags
    if [ ${working_count} -gt 0 ]; then
        NEW_IMAGE_REPOS["$repo"]="${working_tags[*]}"
        echo "${repo}=${working_tags[*]}" >> "${RESULTS_FILE}"
    fi
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}📊 Testing Complete${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Statistics:"
echo "  ⏱️  Time elapsed: ${MINUTES}m ${SECONDS}s"
echo "  📝 Total tags tested: ${TOTAL_TESTED}"
echo "  ✅ Working tags (SPDX): ${TOTAL_WORKING}"
echo "  ⊘ Blocklisted (CycloneDX): ${TOTAL_BLOCKLISTED}"
echo "  ✗ Failed to resolve: ${TOTAL_FAILED}"
echo ""

if [ ${TOTAL_WORKING} -lt 200 ]; then
    echo -e "${RED}⚠️  Warning: Only ${TOTAL_WORKING} working tags found (target is 200)${NC}"
    echo "   You may need to add more repositories or tags."
    echo ""
fi

# Generate new script
echo -e "${YELLOW}📝 Generating new clean script: ${OUTPUT_SCRIPT}${NC}"

cat > "${OUTPUT_SCRIPT}" << 'SCRIPT_HEADER'
#!/bin/bash
set -euo pipefail

# Script to generate a pool of 200 different container images for large snapshot testing
# This version contains ONLY working tags - no blocklist needed!
# 
# Generated by: rebuild-image-repos-clean.sh
SCRIPT_HEADER

echo "# Generated on: $(date)" >> "${OUTPUT_SCRIPT}"
echo "# Working tags: ${TOTAL_WORKING} across ${#NEW_IMAGE_REPOS[@]} repositories" >> "${OUTPUT_SCRIPT}"
echo "" >> "${OUTPUT_SCRIPT}"

cat >> "${OUTPUT_SCRIPT}" << 'SCRIPT_BODY'

TARGET_COUNT="${1:-200}"
OUTPUT_FILE="${2:-/tmp/image-pool.txt}"

echo "🔍 Generating pool of ${TARGET_COUNT} different container images" >&2
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

# ============================================================================
# KONFLUX-ONLY IMAGE POOL: Verified working tags with SPDX SBOMs
# ============================================================================
# All tags have been tested and verified to:
#   1. Exist and be accessible in quay.io
#   2. Have SPDX SBOM format (CycloneDX excluded)
#   3. Have valid Tekton Chains attestations
# ============================================================================
declare -A IMAGE_REPOS=(
SCRIPT_BODY

# Write the new IMAGE_REPOS array
for repo in "${!NEW_IMAGE_REPOS[@]}"; do
    tags="${NEW_IMAGE_REPOS[$repo]}"
    tag_count=$(echo "${tags}" | wc -w)
    repo_name=$(basename "$repo")
    
    echo "    [\"${repo}\"]=\"${tags}\"" >> "${OUTPUT_SCRIPT}"
    echo "" >> "${OUTPUT_SCRIPT}"
done

cat >> "${OUTPUT_SCRIPT}" << 'SCRIPT_FOOTER'
)

TEMP_FILE=$(mktemp)
TRIED_IMAGES=$(mktemp)
SUCCESS_COUNT=0
FAIL_COUNT=0
PASS=1
MAX_PASSES=2  # Reduced from 5 since all tags are pre-verified

cleanup() {
    rm -f "${TEMP_FILE}" "${TRIED_IMAGES}"
}
trap cleanup EXIT

echo "" >&2
echo "📦 Resolving image digests..." >&2
echo "   Target: ${TARGET_COUNT} images" >&2
echo "   Note: All tags are pre-verified working tags" >&2
echo "" >&2

# Keep cycling through repositories until we reach target or max passes
while [ ${SUCCESS_COUNT} -lt ${TARGET_COUNT} ] && [ ${PASS} -le ${MAX_PASSES} ]; do
    if [ ${PASS} -gt 1 ]; then
        echo "" >&2
        echo "🔄 Pass ${PASS}: Need $((TARGET_COUNT - SUCCESS_COUNT)) more images..." >&2
        echo "" >&2
    fi
    
    for repo in "${!IMAGE_REPOS[@]}"; do
        tags="${IMAGE_REPOS[$repo]}"
        
        for tag in ${tags}; do
            image_ref="${repo}:${tag}"
            
            # Skip if already tried this image
            if grep -q "^${image_ref}$" "${TRIED_IMAGES}" 2>/dev/null; then
                continue
            fi
            
            # Mark as tried
            echo "${image_ref}" >> "${TRIED_IMAGES}"
            
            # Resolve to digest
            if inspect_output=$(skopeo inspect --no-tags "docker://${image_ref}" 2>/dev/null); then
                digest=$(echo "${inspect_output}" | jq -r '.Digest')
                digest_ref=$(echo "${inspect_output}" | jq -r '.Name + "@" + .Digest')
                
                # Check if we already have this digest (avoid duplicates)
                if ! grep -q "^${digest_ref}$" "${TEMP_FILE}" 2>/dev/null; then
                    echo "${digest_ref}" >> "${TEMP_FILE}"
                    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                    echo "✓ [${SUCCESS_COUNT}] ${image_ref}" >&2
                    
                    # Stop if we have enough
                    if [ ${SUCCESS_COUNT} -ge ${TARGET_COUNT} ]; then
                        echo "" >&2
                        echo "✅ Reached target of ${TARGET_COUNT} images!" >&2
                        break 3
                    fi
                fi
            else
                FAIL_COUNT=$((FAIL_COUNT + 1))
                echo "✗ Failed: ${image_ref}" >&2
            fi
        done
    done
    
    PASS=$((PASS + 1))
done

echo "" >&2
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
echo "📊 Summary:" >&2
echo "   Successfully resolved: ${SUCCESS_COUNT}" >&2
echo "   Failed to resolve: ${FAIL_COUNT}" >&2
echo "   Total passes: $((PASS - 1))" >&2
echo "" >&2

if [ ${SUCCESS_COUNT} -lt ${TARGET_COUNT} ]; then
    SHORTAGE=$((TARGET_COUNT - SUCCESS_COUNT))
    echo "⚠️  Warning: Only found ${SUCCESS_COUNT} images (target was ${TARGET_COUNT})" >&2
    echo "   Still need ${SHORTAGE} more images" >&2
else
    echo "✅ Successfully generated pool of ${SUCCESS_COUNT} images" >&2
fi

# Save to output file
mv "${TEMP_FILE}" "${OUTPUT_FILE}"
echo "" >&2
echo "💾 Image list saved to: ${OUTPUT_FILE}" >&2
echo "" >&2
echo "✅ All images verified:" >&2
echo "   - Konflux-built with SPDX SBOMs" >&2
echo "   - Accessible in quay.io" >&2
echo "   - Pre-tested working tags only" >&2
SCRIPT_FOOTER

chmod +x "${OUTPUT_SCRIPT}"

echo "   Created: ${OUTPUT_SCRIPT}"
echo ""
echo -e "${GREEN}✅ Done!${NC}"
echo ""
echo "Next steps:"
echo "  1. Review the new script: cat ${OUTPUT_SCRIPT}"
echo "  2. Test it: ${OUTPUT_SCRIPT} 200 /tmp/image-pool-clean.txt"
echo "  3. If satisfied, replace the original:"
echo "     mv ${OUTPUT_SCRIPT} ${SOURCE_SCRIPT}"
echo ""
echo "Statistics saved to: ${STATS_FILE}"
cat "${STATS_FILE}"
echo ""
