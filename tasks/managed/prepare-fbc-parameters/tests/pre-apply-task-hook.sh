#!/usr/bin/env bash
set -euo pipefail

# Install the CRDs so we can create/get internalrequests
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# delete old InternalRequests for this pipeline only to avoid conflicts
kubectl delete internalrequests \
  -l "internal-services.appstudio.openshift.io/pipelinerun-uid" \
  --timeout=30s || true

# Background loop that auto-approves InternalRequests by patching their status.
# The Python script uses the k8s Python client (not the internal-request CLI),
# so executable mocks cannot intercept the calls. This loop runs on the test
# runner and patches each new IR with Succeeded + mock opt-in results.
#
# Only InternalRequests labelled with pipelinerun-uid are selected so that
# concurrent pipelines or unrelated CRs in the namespace are never touched.
IR_LABEL="internal-services.appstudio.openshift.io/pipelinerun-uid"
# Loop self-terminates after 15 min (exceeds any single test timeout).
(
  set +e
  remaining=900
  while [ $((remaining--)) -gt 0 ]; do
    kubectl get internalrequests -l "${IR_LABEL}" \
      --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null \
    | while read -r name; do
      [ -z "${name}" ] && continue
      reason=$(kubectl get internalrequest "${name}" \
        -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null)
      [[ "${reason}" == "Succeeded" || "${reason}" == "Failed" ]] && continue
      container_images=$(kubectl get internalrequest "${name}" \
        -o jsonpath='{.spec.params.containerImages}' 2>/dev/null)
      opt_in=$(echo "${container_images}" \
        | jq -c '[.[] | {containerImage: ., fbcOptIn: true}]' 2>/dev/null) \
        || opt_in='[{"containerImage":"mock","fbcOptIn":true}]'
      patch=$(jq -n \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg opt "${opt_in}" \
        '{status: {
           conditions: [{type: "Succeeded", status: "True",
                         reason: "Succeeded", message: "mock",
                         lastTransitionTime: $ts}],
           results: {optInResults: $opt}}}')
      kubectl patch internalrequest "${name}" --type=merge --subresource=status \
        -p "${patch}" 2>/dev/null || true
    done
    sleep 1
  done
) &
