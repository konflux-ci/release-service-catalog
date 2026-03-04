#!/bin/bash
# Quick Image Report - Developer utility for inspecting the static image pool before running the test.
#
# Queries all Component resources in the namespace and reports for each one:
#   - Whether it has a successfully promoted image digest (status.lastPromotedImage)
#   - Whether it has a PAC secret (required to trigger builds)
#
# Run this before kicking off the large snapshot test to verify the pool is healthy.
# The report is also saved to /tmp/image-report-<timestamp>.txt.
#
# Usage:
#   ./quick-image-report.sh [NAMESPACE]
#
# Example:
#   ./quick-image-report.sh dev-release-team-tenant

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
COMPONENTS=$(kubectl get components -n "${NAMESPACE}" \
  -l test.appstudio.openshift.io/type=multi-version-build \
  -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.labels.test\.appstudio\.openshift\.io/version}{"|"}{.status.lastPromotedImage}{"|"}{.spec.secret}{"\n"}{end}' \
  | grep '^ls-')

# Count non-empty lines only to avoid a spurious count when no components match
TOTAL=$(echo "${COMPONENTS}" | grep -c '.' || true)
VALID=0
WITH_IMAGE=0
NO_SECRET=0

echo "Found ${TOTAL} components"
echo ""

if [ "${TOTAL}" -eq 0 ]; then
    echo "⚠️  No components found matching the selector. Nothing to report."
    echo ""
    echo "Report saved: ${OUTPUT}"
    exit 0
fi

printf "%-50s %-8s %-12s %s\n" "COMPONENT" "VERSION" "STATUS" "IMAGE INFO"
echo "───────────────────────────────────────────────────────────────"

while IFS='|' read -r NAME VERSION STATUS_IMAGE SECRET; do
    [ -z "${NAME}" ] && continue

    if echo "${STATUS_IMAGE}" | grep -q "@sha256:"; then
        HAS_IMAGE="✅"
        WITH_IMAGE=$((WITH_IMAGE + 1))
    else
        HAS_IMAGE="❌"
    fi

    if [ -n "${SECRET}" ] && [ "${SECRET}" != "null" ]; then
        HAS_SECRET="✅"
    else
        HAS_SECRET="❌"
        NO_SECRET=$((NO_SECRET + 1))
    fi

    if [ "${HAS_IMAGE}" == "✅" ] && [ "${HAS_SECRET}" == "✅" ]; then
        STATUS="✅ VALID"
        VALID=$((VALID + 1))
    else
        STATUS="❌ INVALID"
    fi

    printf "%-50s %-8s %-12s Image:%s Secret:%s\n" \
        "${NAME:0:48}" "${VERSION:0:6}" "${STATUS}" "${HAS_IMAGE}" "${HAS_SECRET}"

done <<< "${COMPONENTS}"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "SUMMARY"
echo "═══════════════════════════════════════════════════════════════"
echo ""
pct() { echo $(( $1 * 100 / TOTAL )); }
echo "Total Components:       ${TOTAL}"
echo "Valid (all checks):     ${VALID} ($(pct "${VALID}")%)"
echo "With Images:            ${WITH_IMAGE} ($(pct "${WITH_IMAGE}")%)"
echo ""
echo "Issues:"
echo "  Missing Secret:       ${NO_SECRET}"
echo "  Missing Image:        $(( TOTAL - WITH_IMAGE ))"
echo ""
echo "Report saved: ${OUTPUT}"
