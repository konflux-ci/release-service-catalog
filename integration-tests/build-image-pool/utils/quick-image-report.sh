#!/bin/bash
# Quick Image Report - Fast validation for all components
#
# USAGE:
#   ./quick-image-report.sh [namespace] [component_name_prefix]
#
# ARGUMENTS:
#   namespace              : Kubernetes namespace (default: dev-release-team-tenant)
#   component_name_prefix  : Konflux component name prefix to filter by (default: ls)
#                            Matches components whose name starts with "{prefix}-"
#                            e.g. "ls" reports only ls-v4-* components
#
# ENVIRONMENT (alternative to positional args):
#   NAMESPACE              : Kubernetes namespace
#   COMPONENT_NAME_PREFIX  : Component name prefix
#   COMPONENT_REPO_PREFIX  : GitHub repo name prefix (default: img-pool)
#                            Used to verify the per-component SCM credential secret exists
#                            Expected secret name: pipelines-as-code-secret-${COMPONENT_REPO_PREFIX}-${component_name}

NAMESPACE="${1:-${NAMESPACE:-dev-release-team-tenant}}"
COMPONENT_NAME_PREFIX="${2:-${COMPONENT_NAME_PREFIX:-ls}}"
COMPONENT_REPO_PREFIX="${COMPONENT_REPO_PREFIX:-img-pool}"
OUTPUT="/tmp/image-report-$(date +%Y%m%d-%H%M%S).txt"

exec > >(tee "${OUTPUT}")

echo "═══════════════════════════════════════════════════════════════"
echo "  QUICK IMAGE VALIDATION REPORT"
echo "═══════════════════════════════════════════════════════════════"
echo "Namespace: ${NAMESPACE}"
echo "Prefix:    ${COMPONENT_NAME_PREFIX}-"
echo "Time: $(date)"
echo ""

# Get components with relevant data in one query, filtered by prefix
# Validation source of truth: status.lastPromotedImage (built/promoted image digest)
ALL_COMPONENTS_RAW=$(kubectl get components -n "${NAMESPACE}" \
  -l test.appstudio.openshift.io/type=multi-version-build \
  -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.labels.test\.appstudio\.openshift\.io/version}{"|"}{.spec.containerImage}{"|"}{.status.lastPromotedImage}{"|"}{.spec.secret}{"|"}{.metadata.annotations.build\.appstudio\.openshift\.io/request-platforms}{"\n"}{end}')

# Filter to the requested prefix
COMPONENTS=$(echo "${ALL_COMPONENTS_RAW}" | grep "^${COMPONENT_NAME_PREFIX}-" || true)

if [ -z "${COMPONENTS}" ]; then
    echo "No components found with prefix '${COMPONENT_NAME_PREFIX}-' in namespace '${NAMESPACE}'"
    exit 0
fi

TOTAL=$(echo "${COMPONENTS}" | wc -l)
VALID=0
WITH_IMAGE=0
NO_SECRET=0
MULTI_ARCH=0
SINGLE_ARCH=0

echo "Found ${TOTAL} components matching prefix '${COMPONENT_NAME_PREFIX}-'"
echo ""

# Pre-fetch all SCM credential secrets in one batch query.
# Expected secret name: pipelines-as-code-secret-${COMPONENT_REPO_PREFIX}-${component_name}
# These secrets have label appstudio.redhat.com/credentials=scm and tell PAC to use a PAT
# instead of the GitHub App (avoiding Error 70 on repos not covered by the App installation).
SCM_SECRETS=$(kubectl get secrets -n "${NAMESPACE}" \
  -l "appstudio.redhat.com/credentials=scm" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

printf "%-50s %-8s %-12s %s\n" "COMPONENT" "VERSION" "STATUS" "IMAGE INFO"
echo "───────────────────────────────────────────────────────────────"

while IFS='|' read -r NAME VERSION SPEC_IMAGE STATUS_IMAGE SECRET PLATFORMS; do
    # Check image (status.lastPromotedImage only)
    # NOTE: spec.containerImage may be tag-only or patched during recovery; it is NOT a build/promotion signal.
    IMAGE="${STATUS_IMAGE}"
    
    if echo "${IMAGE}" | grep -q "@sha256:"; then
        HAS_IMAGE="✅"
        WITH_IMAGE=$((WITH_IMAGE + 1))
    else
        HAS_IMAGE="❌"
    fi
    
    # Check per-component SCM credential secret exists with the right label.
    # The secret name follows the pattern: pipelines-as-code-secret-${COMPONENT_REPO_PREFIX}-${NAME}
    # This secret is what allows PAC to use a PAT for GitHub auth instead of the GitHub App.
    EXPECTED_SECRET="pipelines-as-code-secret-${COMPONENT_REPO_PREFIX}-${NAME}"
    if echo "${SCM_SECRETS}" | grep -qx "${EXPECTED_SECRET}"; then
        HAS_SECRET="✅"
    else
        HAS_SECRET="❌"
        NO_SECRET=$((NO_SECRET + 1))
    fi
    
    # Check multi-arch
    # No annotation means single-arch (Konflux default when no request-platforms is set)
    if [ -n "${PLATFORMS}" ] && [ "${PLATFORMS}" != "null" ] && [ $(echo "${PLATFORMS}" | tr ',' '\n' | wc -l) -gt 1 ]; then
        HAS_MULTIARCH="✅"
        MULTI_ARCH=$((MULTI_ARCH + 1))
    else
        HAS_MULTIARCH="❌"
        SINGLE_ARCH=$((SINGLE_ARCH + 1))
    fi
    
    # Overall status
    if [ "${HAS_IMAGE}" == "✅" ] && [ "${HAS_SECRET}" == "✅" ]; then
        STATUS="✅ VALID"
        VALID=$((VALID + 1))
    else
        STATUS="❌ INVALID"
    fi
    
    printf "%-50s %-8s %-12s Image:%s Secret:%s Multi:%s\n" \
        "${NAME:0:48}" "${VERSION:0:6}" "${STATUS}" "${HAS_IMAGE}" "${HAS_SECRET}" "${HAS_MULTIARCH}"
        
done <<< "${COMPONENTS}"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "SUMMARY"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Total Components:       ${TOTAL}"
echo "Valid (all checks):     ${VALID} ($(( VALID * 100 / TOTAL ))%)"
echo "With Images:            ${WITH_IMAGE} ($(( WITH_IMAGE * 100 / TOTAL ))%)"
echo ""
echo "Multi-Arch Distribution:"
echo "  🌍 Multi-arch:         ${MULTI_ARCH} ($(( MULTI_ARCH * 100 / TOTAL ))%)"
echo "  🖥️ Single-arch:        ${SINGLE_ARCH}"
echo "  ❓ Not specified:      $(( TOTAL - MULTI_ARCH - SINGLE_ARCH ))"
echo ""
echo "Issues:"
echo "  Missing SCM secret:   ${NO_SECRET}  (pipelines-as-code-secret-${COMPONENT_REPO_PREFIX}-<name>)"
echo "  Missing Image:        $(( TOTAL - WITH_IMAGE ))"
echo ""
echo "Report saved: ${OUTPUT}"
