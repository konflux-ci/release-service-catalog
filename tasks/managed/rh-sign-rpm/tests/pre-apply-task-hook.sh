#!/usr/bin/env bash
#
# Install the CRDs so we can create/get them
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# delete old InternalRequests
kubectl delete internalrequests --all -A

# Delete pipeline for RPM signing
kubectl delete pipeline/rpm-signing-pipeline --ignore-not-found

cat > "/tmp/rpm-signing-pipeline.json" << EOF
{
  "apiVersion": "tekton.dev/v1",
  "kind": "Pipeline",
  "metadata": {
    "name": "rpm-signing-pipeline",
    "namespace": "default"
  },
  "spec": {
    "params": [
      {
        "name": "pipeline_image",
        "type": "string"
      },
      {
        "name": "artifact_json",
        "type": "string"
      },
      {
        "name": "kerberos_principal",
        "type": "string"
      },
      {
        "name": "kerberos_keytab",
        "type": "string"
      },
      {
        "name": "kerberos_keytab_secret",
        "type": "string"
      },
      {
        "name": "signing_alias",
        "type": "string"
      },
      {
        "name": "requester",
        "type": "string"
      },
      {
        "name": "force",
        "type": "string"
      },
      {
        "name": "artifact_storage_secret",
        "type": "string"
      },
      {
        "name": "destination_artifact_storage_domain",
        "type": "string"
      },
      {
        "name": "taskGitUrl",
        "type": "string"
      },
      {
        "name": "taskGitRevision",
        "type": "string"
      }
    ],
    "tasks": [
      {
        "name": "sign-rpm",
        "taskSpec": {
          "steps": [
            {
              "image": "bash:3.2",
              "name": "sign",
              "script": "echo Signing RPMs"
            }
          ]
        }
      }
    ]
  }
}
EOF
kubectl create -f /tmp/rpm-signing-pipeline.json

# Create a dummy pulp secret for idempotency check
kubectl delete secret mock-pulp-secret --ignore-not-found
kubectl create secret generic mock-pulp-secret --from-literal=cli.toml='base_url = "https://console.redhat.com"
client_id = "mock-client-id"
client_secret = "mock-client-secret"
'

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"
