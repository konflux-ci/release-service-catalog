#!/bin/bash
# Quick Image Report - Fast validation for all components

NAMESPACE="${1:-dev-release-team-tenant}"
OUTPUT="/tmp/image-report-$(date +%Y%m%d-%H%M%S).txt"

exec > >(tee "${OUTPUT}")

echo "═══════════════════════════════════════════════════════════════"
echo "  QUICK IMAGE VALIDATION REPORT"
echo "═══════════════════════════════════════════════════════════════"
echo "Namespace: ${NAMESPACE}"
echo "Time: $(date)"
echo ""

# Get components with relevant data in one query
# Validation source of truth: status.lastPromotedImage (built/promoted image digest)
COMPONENTS_JSON=$(kubectl get components -n "${NAMESPACE}" \
  -l test.appstudio.openshift.io/type=multi-version-build \
  -o json 2>/dev/null || echo '{"items":[]}')

COMPONENTS=$(echo "${COMPONENTS_JSON}" | jq -r '
  .items[]? |
  [
    (.metadata.name // ""),
    (.metadata.labels["test.appstudio.openshift.io/version"] // ""),
    (.spec.containerImage // ""),
    (.status.lastPromotedImage // ""),
    (.spec.secret // ""),
    (.metadata.annotations["build.appstudio.openshift.io/request-platforms"] // "")
  ] | join("|")
')

TOTAL=$(echo "${COMPONENTS_JSON}" | jq -r '.items | length')
VALID=0
WITH_IMAGE=0
NO_SECRET=0
MULTI_ARCH=0
SINGLE_ARCH=0

pct() {
    local part="${1:-0}"
    local whole="${2:-0}"
    if [ "${whole}" -eq 0 ]; then
        echo "0"
    else
        echo $(( part * 100 / whole ))
    fi
}

echo "Found ${TOTAL} components"
echo ""
printf "%-50s %-8s %-12s %s\n" "COMPONENT" "VERSION" "STATUS" "IMAGE INFO"
echo "───────────────────────────────────────────────────────────────"

while IFS='|' read -r NAME VERSION SPEC_IMAGE STATUS_IMAGE SECRET PLATFORMS; do
    [ -z "${NAME}" ] && continue

    # Check image (status.lastPromotedImage only)
    # NOTE: spec.containerImage may be tag-only or patched during recovery; it is NOT a build/promotion signal.
    IMAGE="${STATUS_IMAGE}"
    
    if echo "${IMAGE}" | grep -q "@sha256:"; then
        HAS_IMAGE="✅"
        WITH_IMAGE=$((WITH_IMAGE + 1))
    else
        HAS_IMAGE="❌"
    fi
    
    # Check secret
    if [ -n "${SECRET}" ] && [ "${SECRET}" != "null" ]; then
        HAS_SECRET="✅"
    else
        HAS_SECRET="❌"
        NO_SECRET=$((NO_SECRET + 1))
    fi
    
    # Check multi-arch
    if [ -n "${PLATFORMS}" ] && [ "${PLATFORMS}" != "null" ]; then
        ARCH_COUNT=$(echo "${PLATFORMS}" | tr ',' '\n' | wc -l)
        if [ ${ARCH_COUNT} -gt 1 ]; then
            HAS_MULTIARCH="🌍"
            MULTI_ARCH=$((MULTI_ARCH + 1))
        else
            HAS_MULTIARCH="📱"
            SINGLE_ARCH=$((SINGLE_ARCH + 1))
        fi
    else
        HAS_MULTIARCH="❓"
    fi
    
    # Overall status
    if [ "${HAS_IMAGE}" == "✅" ] && [ "${HAS_SECRET}" == "✅" ]; then
        STATUS="✅ VALID"
        VALID=$((VALID + 1))
    else
        STATUS="❌ INVALID"
    fi
    
    # Print row (same format as original, PAC replaced with Multi-Arch)
    printf "%-50s %-8s %-12s Image:%s Secret:%s Multi:%s\n" \
        "${NAME:0:48}" "${VERSION:0:6}" "${STATUS}" "${HAS_IMAGE}" "${HAS_SECRET}" "${HAS_MULTIARCH}"
        
done <<< "${COMPONENTS}"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "SUMMARY"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Total Components:       ${TOTAL}"
echo "Valid (all checks):     ${VALID} ($(pct "${VALID}" "${TOTAL}")%)"
echo "With Images:            ${WITH_IMAGE} ($(pct "${WITH_IMAGE}" "${TOTAL}")%)"
echo ""
echo "Multi-Arch Distribution:"
echo "  🌍 Multi-arch:         ${MULTI_ARCH} ($(pct "${MULTI_ARCH}" "${TOTAL}")%)"
echo "  📱 Single-arch:        ${SINGLE_ARCH}"
echo "  ❓ Not specified:      $(( TOTAL - MULTI_ARCH - SINGLE_ARCH ))"
echo ""
echo "Issues:"
echo "  Missing Secret:       ${NO_SECRET}"
echo "  Missing Image:        $(( TOTAL - WITH_IMAGE ))"
echo ""
echo "Report saved: ${OUTPUT}"
