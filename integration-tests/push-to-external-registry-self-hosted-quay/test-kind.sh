#!/usr/bin/env bash
#
# test-kind.sh - E2E test for push-to-external-registry on self-hosted Quay (Kind cluster).
#
# This script is a standalone test that runs against a Kind cluster where Quay has
# been deployed (via the deploy-konflux-ci task with skip-quay=false). It initializes
# Quay (creates admin user, org, robot account, copies a source image), creates all
# necessary Kubernetes resources, triggers a release via a Snapshot, and verifies the
# release pipeline completes successfully.
#
# Prerequisites:
#   - Kind cluster with Konflux and Quay deployed (deploy-konflux-ci task)
#   - KUBECONFIG set to the Kind cluster
#
# Environment Variables:
#   VAULT_PASSWORD                - Ansible vault password for decrypting secrets (required)
#   RELEASE_CATALOG_GIT_URL       - Git URL for the release service catalog (optional)
#   RELEASE_CATALOG_GIT_REVISION  - Git revision for the release service catalog (optional)

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# shellcheck source=../lib/test-functions.sh
source "${SCRIPT_DIR}/../lib/test-functions.sh"

VAULT_PASSWORD_FILE=$(mktemp)
export VAULT_PASSWORD_FILE
set +x
echo "${VAULT_PASSWORD:?}" > "${VAULT_PASSWORD_FILE}"

PF_PID=""
VERIFY_PF_PID=""
cleanup() {
    kill "${PF_PID}" 2>/dev/null || true
    kill "${VERIFY_PF_PID}" 2>/dev/null || true
    rm -f "${VAULT_PASSWORD_FILE}" 2>/dev/null || true
}
trap cleanup EXIT

# --- Decrypt vault secrets (early, needed for config values) ---
echo "=== Decrypting vault secrets ==="
decrypt_secrets "${SCRIPT_DIR}"

# --- Configuration ---
uuid=$(openssl rand -hex 4)
uuid="${uuid:0:8}"

export originating_tool="push-to-external-registry-self-hosted-quay"
export application_name="appstudio"
export component_name="dc-metro-map"
export tenant_namespace="ex-registry-sh-${uuid}"
export managed_namespace="ex-registry-sh-managed-${uuid}"
export managed_sa_name="release-service-account"
export release_plan_name="source-releaseplan"
export release_plan_admission_name="demo"
export ec_policy_name="ex-registry-sh-policy-${uuid}"
export RELEASE_CATALOG_GIT_URL="${RELEASE_CATALOG_GIT_URL:-https://github.com/konflux-ci/release-service-catalog}"
export RELEASE_CATALOG_GIT_REVISION="${RELEASE_CATALOG_GIT_REVISION:-development}"

export git_source_url="https://github.com/redhat-appstudio-qe/dc-metro-map-release"
export git_source_revision="d49914874789147eb2de9bb6a12cd5d150bfff92"

QUAY_INTERNAL_HOST="quay-service.quay"
ADMIN_USER="quayadmin"
ADMIN_PASSWORD=$(yq 'select(.metadata.name == "quay-admin-credentials") | .stringData.password' \
    "${SCRIPT_DIR}/resources/managed/secrets/managed-secrets.yaml")
ADMIN_EMAIL="admin@local.dev"
ORG_NAME="test-org"
ROBOT_NAME="release-bot"
SOURCE_IMAGE="quay.io/hacbs-release-tests/dcmetromap"
DEST_REPO="${ORG_NAME}/$(basename "${SOURCE_IMAGE}")"

RELEASE_TIMEOUT=3600  # 60 minutes
RELEASE_POLL_INTERVAL=10
RELEASE_APPEAR_TIMEOUT=300  # 5 minutes

# --- Step 1: Initialize Quay ---
echo "=== Initializing Quay ==="

echo "  Waiting for Quay pods..."
kubectl wait --for=condition=Ready --timeout=300s -n quay -l app=quay pod

kubectl port-forward -n quay svc/quay-service 8443:443 &
PF_PID=$!
sleep 3


QUAY_HOST_URL="https://localhost:8443"

echo "  Waiting for Quay API to become healthy..."
for i in $(seq 1 60); do
    if curl -4 -sk "${QUAY_HOST_URL}/health/instance" 2>/dev/null \
        | grep -q '"status_code":200'; then
        echo "  Quay is healthy"
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "ERROR: Quay did not become healthy within 120s"
        exit 1
    fi
    sleep 2
done

echo "  Creating admin user '${ADMIN_USER}'..."
INIT_RESPONSE=$(curl -4 -sk -X POST "${QUAY_HOST_URL}/api/v1/user/initialize" \
    -H "Content-Type: application/json" \
    -d "{
        \"username\": \"${ADMIN_USER}\",
        \"password\": \"${ADMIN_PASSWORD}\",
        \"email\": \"${ADMIN_EMAIL}\",
        \"access_token\": true
    }")

if echo "$INIT_RESPONSE" | jq -e '.access_token' &>/dev/null; then
    TOKEN=$(echo "$INIT_RESPONSE" | jq -r '.access_token')
    echo "  Admin user created"
else
    echo "ERROR: Failed to create admin: $(echo "$INIT_RESPONSE" | jq -r '.message // "unknown"')"
    exit 1
fi

echo "  Creating organization '${ORG_NAME}'..."
ORG_RESPONSE=$(curl -4 -sk -X POST "${QUAY_HOST_URL}/api/v1/organization/" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"${ORG_NAME}\", \"email\": \"org@local.dev\"}")

if [ "$ORG_RESPONSE" != '"Created"' ]; then
    echo "ERROR: Failed to create organization: $ORG_RESPONSE"
    exit 1
fi

echo "  Creating robot '${ORG_NAME}+${ROBOT_NAME}'..."
ROBOT_RESPONSE=$(curl -4 -sk -X PUT \
    "${QUAY_HOST_URL}/api/v1/organization/${ORG_NAME}/robots/${ROBOT_NAME}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"description\": \"Robot account for release pipeline\"}")

ROBOT_TOKEN=$(echo "$ROBOT_RESPONSE" | jq -r '.token // empty')
if [ -z "$ROBOT_TOKEN" ]; then
    echo "ERROR: Failed to create robot account: $ROBOT_RESPONSE"
    exit 1
fi

echo "  Adding robot to owners team..."
TEAM_RESPONSE=$(curl -4 -sk -X PUT \
    "${QUAY_HOST_URL}/api/v1/organization/${ORG_NAME}/team/owners/members/${ORG_NAME}+${ROBOT_NAME}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json")

if ! echo "$TEAM_RESPONSE" | jq -e '.name' &>/dev/null; then
    echo "ERROR: Failed to add robot to owners team: $TEAM_RESPONSE"
    exit 1
fi

robot_user="${ORG_NAME}+${ROBOT_NAME}"
robot_password="${ROBOT_TOKEN}"
admin_token="${TOKEN}"

# Copy source image + cosign signatures into Quay via in-cluster pod
echo "  Copying ${SOURCE_IMAGE} to ${QUAY_INTERNAL_HOST}/${DEST_REPO}..."

DOCKER_AUTH=$(printf '%s' "${robot_user}:${robot_password}" | base64 -w0)
kubectl create secret generic cosign-docker-config --namespace=default \
    --from-literal=config.json="$(printf '{"auths":{"%s":{"auth":"%s"}}}' \
        "${QUAY_INTERNAL_HOST}" "${DOCKER_AUTH}")" \
    --dry-run=client -o yaml | kubectl apply -f -

set +e
COPY_OUTPUT=$(kubectl run copy-images --rm -i --restart=Never --namespace=default --pod-running-timeout=10m \
    --image=quay.io/konflux-ci/tekton-integration-catalog/utils:latest \
    --override-type=strategic \
    --overrides="$(jq -n \
        --arg source "${SOURCE_IMAGE}" \
        --arg dest "${QUAY_INTERNAL_HOST}/${DEST_REPO}" \
        '{
            spec: {
                containers: [{
                    name: "copy-images",
                    image: "quay.io/konflux-ci/tekton-integration-catalog/utils:latest",
                    command: ["cosign", "copy", "--allow-insecure-registry"],
                    args: [$source, $dest],
                    env: [{name: "DOCKER_CONFIG", value: "/docker-config"}],
                    volumeMounts: [{name: "docker-config", mountPath: "/docker-config", readOnly: true}]
                }],
                volumes: [{
                    name: "docker-config",
                    secret: {secretName: "cosign-docker-config"}
                }]
            }
        }')" 2>&1)
copy_rc=$?
set -e
echo "  Copy output: $COPY_OUTPUT"
if [[ $copy_rc -ne 0 ]]; then
    echo "ERROR: Failed to copy image/signatures into self-hosted Quay"
    exit 1
fi

kubectl delete secret cosign-docker-config --namespace=default --ignore-not-found &>/dev/null

echo "  Querying Quay API for image digest..."
TAG_RESPONSE=$(curl -4 -sk "${QUAY_HOST_URL}/api/v1/repository/${DEST_REPO}/tag/" \
    -H "Authorization: Bearer ${TOKEN}")
image_digest=$(echo "$TAG_RESPONSE" | jq -r '.tags[0].manifest_digest // empty')
if [[ "${image_digest}" != sha256:* ]]; then
    echo "ERROR: Failed to determine image digest from Quay API"
    echo "  Response: ${TAG_RESPONSE}"
    exit 1
fi

kill "${PF_PID}" 2>/dev/null || true
PF_PID=""

quay_host="${QUAY_INTERNAL_HOST}"

echo "  Quay initialization complete!"
echo "    Internal host: ${quay_host}"
echo "    Image: ${quay_host}/${DEST_REPO}@${image_digest}"

# --- Step 2: Set derived exports ---
export sample_image="${quay_host}/${DEST_REPO}@${image_digest}"
export snapshot_name="snapshot-sample-${uuid}"
export released_image_push_repo="${quay_host}/test-org/released-${component_name}"
export ta_oci_storage="${quay_host}/test-org/trusted-artifacts"

echo "  Sample image: ${sample_image}"
echo "  Released image repo: ${released_image_push_repo}"
echo "  TA OCI storage: ${ta_oci_storage}"

# --- Step 3: Create namespaces ---
echo "=== Creating namespaces ==="
kubectl create namespace "${tenant_namespace}"
kubectl create namespace "${managed_namespace}"
echo "  Created: ${tenant_namespace}, ${managed_namespace}"

# --- Step 4: Create dynamic secrets ---
echo "=== Creating secrets ==="

kubectl create secret docker-registry hacbs-release-tests-token \
    --namespace="${managed_namespace}" \
    --docker-server="${quay_host}" \
    --docker-username="${robot_user}" \
    --docker-password="${robot_password}"

kubectl create secret docker-registry release-catalog-trusted-artifacts-quay-secret \
    --namespace="${managed_namespace}" \
    --docker-server="${quay_host}" \
    --docker-username="${robot_user}" \
    --docker-password="${robot_password}"

kubectl create secret generic quay-api-token \
    --namespace="${managed_namespace}" \
    --from-literal=token="${admin_token}"

echo "  Created: hacbs-release-tests-token, release-catalog-trusted-artifacts-quay-secret,"
echo "           quay-api-token"

# --- Step 5: Apply kustomize resource templates ---
echo "=== Applying Kubernetes resources ==="

tmpDir=$(mktemp -d)

echo "  Resolving symlinks in resources directories..."
resolve_symlinks_for_kustomize "${SCRIPT_DIR}/resources/managed" "$tmpDir/managed"
resolve_symlinks_for_kustomize "${SCRIPT_DIR}/resources/tenant" "$tmpDir/tenant"

echo "  Building and applying managed resources..."
kubectl kustomize "$tmpDir/managed" | perl -pe 's/\$\{([^}]+)\}/$ENV{$1}/ge' > "${tmpDir}/managed-resources.yaml"
kubectl apply -f "${tmpDir}/managed-resources.yaml"

echo "  Building and applying tenant resources..."
kubectl kustomize "$tmpDir/tenant" | perl -pe 's/\$\{([^}]+)\}/$ENV{$1}/ge' > "${tmpDir}/tenant-resources.yaml"
kubectl create -f "${tmpDir}/tenant-resources.yaml"

rm -rf "${tmpDir}"

# --- Step 6: Wait for Release CR ---
echo "=== Waiting for Release CR ==="

release_name=""
elapsed=0
while [ -z "$release_name" ]; do
    if [ $elapsed -ge $RELEASE_APPEAR_TIMEOUT ]; then
        echo "ERROR: Timed out waiting for Release CR to appear after ${RELEASE_APPEAR_TIMEOUT}s"
        kubectl get releases -n "${tenant_namespace}" -o wide 2>/dev/null || true
        exit 1
    fi
    sleep "$RELEASE_POLL_INTERVAL"
    elapsed=$((elapsed + RELEASE_POLL_INTERVAL))
    release_name=$(kubectl get release -n "${tenant_namespace}" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1)
    echo -n "."
done
echo ""
echo "  Found Release: ${release_name}"

# --- Step 7: Wait for Release PipelineRun to complete ---
echo "=== Waiting for Release PipelineRun ==="

plr_name=""
elapsed=0
while [ -z "$plr_name" ]; do
    if [ $elapsed -ge $RELEASE_APPEAR_TIMEOUT ]; then
        echo "ERROR: Timed out waiting for managed PipelineRun to appear after ${RELEASE_APPEAR_TIMEOUT}s"
        exit 1
    fi
    sleep "$RELEASE_POLL_INTERVAL"
    elapsed=$((elapsed + RELEASE_POLL_INTERVAL))
    plr_name=$(kubectl get pipelinerun -n "${managed_namespace}" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1)
    echo -n "."
done
echo ""
echo "  Found PipelineRun: ${plr_name}"

echo "  Waiting for PipelineRun to finish..."
elapsed=0
while true; do
    if [ $elapsed -ge $RELEASE_TIMEOUT ]; then
        echo "ERROR: Timed out waiting for PipelineRun to complete after ${RELEASE_TIMEOUT}s"
        kubectl get pipelinerun "${plr_name}" -n "${managed_namespace}" -o yaml 2>/dev/null || true
        exit 1
    fi
    sleep "$RELEASE_POLL_INTERVAL"
    elapsed=$((elapsed + RELEASE_POLL_INTERVAL))

    status=$(kubectl get pipelinerun "${plr_name}" -n "${managed_namespace}" \
        -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null || true)

    if [ "$status" == "True" ]; then
        echo ""
        echo "  PipelineRun completed successfully"
        break
    elif [ "$status" == "False" ]; then
        echo ""
        echo "ERROR: PipelineRun failed"
        diagnose_failed_pipelinerun "${plr_name}" "${managed_namespace}"
        exit 1
    fi

    if (( elapsed % 60 == 0 )); then
        echo "  ... still waiting (${elapsed}s elapsed)"
    fi
done

# --- Step 8: Verify Release status and artifacts ---
echo "=== Verifying Release status and artifacts ==="

release_json=$(kubectl get release "${release_name}" -n "${tenant_namespace}" -o json)
failures=0

released=$(echo "$release_json" | jq -r '.status.conditions[]? | select(.type=="Released") | .status')
if [ "$released" != "True" ]; then
    echo "ERROR: Release is not marked as Released"
    echo "$release_json" | jq '.status'
    exit 1
fi
echo "  Release ${release_name} is marked as Released"

image_url=$(echo "$release_json" | jq -r '.status.artifacts.images[0]?.urls[0] // ""')
image_arch=$(echo "$release_json" | jq -r '.status.artifacts.images[0]?.arches[0] // ""')
image_shasum=$(echo "$release_json" | jq -r '.status.artifacts.images[0]?.shasum // ""')

echo "  Checking Image URL..."
if [ -n "${image_url}" ]; then
    echo "    image_url: ${image_url}"
else
    echo "    ERROR: image_url was empty"
    failures=$((failures+1))
fi

echo "  Checking Image Arch..."
if [ -n "${image_arch}" ]; then
    echo "    image_arch: ${image_arch}"
else
    echo "    ERROR: image_arch was empty"
    failures=$((failures+1))
fi

echo "  Checking Image Shasum..."
if [ -n "${image_shasum}" ]; then
    echo "    image_shasum: ${image_shasum}"
else
    echo "    ERROR: image_shasum was empty"
    failures=$((failures+1))
fi

echo "  Checking for ':latest' tag..."
image_urls=$(echo "$release_json" | jq -r '.status.artifacts.images[0].urls[]? // ""')
if echo "${image_urls}" | grep -q ":latest"; then
    echo "    Found ':latest' tag"
else
    echo "    ERROR: Missing ':latest' tag from defaults.tags"
    echo "    URLs found: ${image_urls}"
    failures=$((failures+1))
fi

echo "  Verifying released image exists in Quay..."
kubectl port-forward -n quay svc/quay-service 8443:443 &
VERIFY_PF_PID=$!
sleep 4

RELEASED_REPO="${released_image_push_repo#"${QUAY_INTERNAL_HOST}/"}"
VERIFY_RESPONSE=$(curl -4 -sk "https://localhost:8443/api/v1/repository/${RELEASED_REPO}/tag/" \
    -H "Authorization: Bearer ${TOKEN}" 2>/dev/null)

tag_count=$(echo "$VERIFY_RESPONSE" | jq -r '.tags | length // 0' 2>/dev/null)
if [ "${tag_count}" -gt 0 ]; then
    echo "    Released image found in Quay with ${tag_count} tag(s)"
else
    echo "    ERROR: No tags found in released repository ${RELEASED_REPO}"
    echo "    Response: ${VERIFY_RESPONSE}"
    failures=$((failures+1))
fi

echo "  Verifying released repository is public..."
VISIBILITY_RESPONSE=$(curl -4 -sk "https://localhost:8443/api/v1/repository/${RELEASED_REPO}" \
    -H "Authorization: Bearer ${TOKEN}" 2>/dev/null)
is_public=$(echo "$VISIBILITY_RESPONSE" | jq -r '.is_public // false' 2>/dev/null)
if [ "$is_public" = "true" ]; then
    echo "    Released repository is public"
else
    echo "    ERROR: Released repository is not public"
    echo "    Response: ${VISIBILITY_RESPONSE}"
    failures=$((failures+1))
fi

kill "${VERIFY_PF_PID}" 2>/dev/null || true
VERIFY_PF_PID=""

if [ "${failures}" -gt 0 ]; then
    echo ""
    echo "ERROR: Verification FAILED with ${failures} failure(s)"
    exit 1
fi

echo ""
echo "=== E2E test completed successfully ==="
