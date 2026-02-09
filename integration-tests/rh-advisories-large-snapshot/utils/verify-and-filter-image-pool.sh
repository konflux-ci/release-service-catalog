#!/bin/bash
set -euo pipefail

# Script to verify and filter image pool for apply-mapping compatibility
# Filters out images that cause "Cannot iterate over null" errors

INPUT_FILE="${1:-/tmp/image-pool-200.txt}"
OUTPUT_FILE="${2:-${INPUT_FILE}.filtered}"

if [ ! -f "${INPUT_FILE}" ]; then
    echo "❌ Error: Input file not found: ${INPUT_FILE}" >&2
    exit 1
fi

echo "🔍 Verifying and filtering image pool..." >&2
echo "   Input: ${INPUT_FILE}" >&2
echo "   Output: ${OUTPUT_FILE}" >&2
echo "" >&2

TEMP_GOOD=$(mktemp)
TEMP_BAD=$(mktemp)
cleanup() {
    rm -f "${TEMP_GOOD}" "${TEMP_BAD}"
}
trap cleanup EXIT

total=0
good=0
bad=0

while IFS= read -r image; do
    [ -z "$image" ] && continue
    
    total=$((total + 1))
    echo -n "  [$total] Checking $image... " >&2
    
    # Get raw manifest
    if ! manifest=$(skopeo inspect --raw "docker://${image}" 2>/dev/null); then
        echo "❌ SKIP (cannot inspect)" >&2
        echo "$image: cannot inspect" >> "${TEMP_BAD}"
        bad=$((bad + 1))
        continue
    fi
    
    # Check if manifest is valid JSON
    if ! echo "$manifest" | jq empty 2>/dev/null; then
        echo "❌ SKIP (invalid JSON)" >&2
        echo "$image: invalid JSON" >> "${TEMP_BAD}"
        bad=$((bad + 1))
        continue
    fi
    
    # CRITICAL: Check if this will work with apply-mapping's get-image-architectures
    # The function expects either:
    # 1. Manifest list with .manifests[] array
    # 2. Single-arch with root .mediaType field
    
    # Check for manifest list (multi-arch)
    if echo "$manifest" | jq -e '.manifests' >/dev/null 2>&1; then
        echo "✅ OK (manifest list)" >&2
        echo "$image" >> "${TEMP_GOOD}"
        good=$((good + 1))
        continue
    fi
    
    # Check for root mediaType (required by apply-mapping)
    if ! echo "$manifest" | jq -e '.mediaType' >/dev/null 2>&1; then
        echo "❌ SKIP (missing root mediaType - causes apply-mapping failure)" >&2
        echo "$image: missing root mediaType" >> "${TEMP_BAD}"
        bad=$((bad + 1))
        continue
    fi
    
    # Single-arch image with mediaType - should be OK
    echo "✅ OK (single-arch with mediaType)" >&2
    echo "$image" >> "${TEMP_GOOD}"
    good=$((good + 1))
    
done < "${INPUT_FILE}"

# Write good images to output
if [ -f "${TEMP_GOOD}" ]; then
    mv "${TEMP_GOOD}" "${OUTPUT_FILE}"
fi

echo "" >&2
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
echo "📊 Verification Results:" >&2
echo "   Total:   $total" >&2
echo "   Good:    $good" >&2
echo "   Filtered: $bad" >&2
echo "" >&2

if [ $bad -gt 0 ]; then
    echo "⚠️  Filtered images (incompatible with apply-mapping):" >&2
    cat "${TEMP_BAD}" >&2
    echo "" >&2
fi

if [ $good -eq 0 ]; then
    echo "❌ Error: No valid images remaining!" >&2
    exit 1
fi

echo "✅ Filtered image pool saved to: ${OUTPUT_FILE}" >&2
echo "   Compatible images: $good" >&2
