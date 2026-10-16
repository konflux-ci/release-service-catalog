#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Create a ConfigMap with mock scripts
kubectl delete configmap push-rpm-to-koji-mocks --ignore-not-found
kubectl create configmap push-rpm-to-koji-mocks \
  --from-file=koji="${SCRIPT_DIR}/mocks/koji" \
  --from-file=kinit="${SCRIPT_DIR}/mocks/kinit" \
  --from-file=oras="${SCRIPT_DIR}/mocks/oras" \
  --from-file=select-oci-auth="${SCRIPT_DIR}/mocks/select-oci-auth"

# Add a volume for the mocks ConfigMap
yq -i '.spec.volumes += [{"name": "mocks", "configMap": {"name": "push-rpm-to-koji-mocks", "defaultMode": 493}}]' \
  "${TASK_PATH}"

# Mount mocks and prepend to PATH in the push-rpm-to-koji step
yq -i '(.spec.steps[] | select(.name == "push-rpm-to-koji").volumeMounts) += [{"name": "mocks", "mountPath": "/usr/local/bin/mocks"}]' \
  "${TASK_PATH}"

# Prepend mocks directory to PATH in the script
yq -i '(.spec.steps[] | select(.name == "push-rpm-to-koji").script) = "#!/usr/bin/env bash\nset -eo pipefail\nexport PATH=/usr/local/bin/mocks:$PATH\npython3 -m release_service_utils.tasks.managed.push_rpm_to_koji"' \
  "${TASK_PATH}"

# Delete existing secrets if they exist
kubectl delete secret push-koji-test --ignore-not-found

# Create the fake secrets for koji
kubectl create secret generic push-koji-test \
  --from-literal=base64_keytab="$(base64 <<< "some keytab")"
