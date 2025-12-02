#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# The task uses command/args instead of script, so we need to convert it to a script
# that includes our mocks and then calls the original command.

# Create a wrapper script that includes mocks and calls the original command
cat > /tmp/wrapped-script.sh <<'EOF'
#!/usr/bin/env bash
set -eux
EOF

# Append the mocks
cat "$SCRIPT_DIR/mocks.sh" >> /tmp/wrapped-script.sh

# Add the original command call with its args
cat >> /tmp/wrapped-script.sh <<'EOF'

/home/scripts/bash/tasks/internal/check-embargoed-cves.sh --cves "$(params.cves)"
EOF

# Replace command/args with script in the task
yq -i '.spec.steps[0].script = load_str("/tmp/wrapped-script.sh")' "$TASK_PATH"
yq -i 'del(.spec.steps[0].command)' "$TASK_PATH"
yq -i 'del(.spec.steps[0].args)' "$TASK_PATH"

# Create a dummy osidb secret (and delete it first if it exists)
# The secret name is hardcoded in the task so the mock secret name can't have the task name in it
kubectl delete secret osidb-service-account --ignore-not-found
kubectl create secret generic osidb-service-account --from-literal=name=myname --from-literal=base64_keytab=OWEyMmJmYzgtYzJkZi00Y2VhLWJkNWItYjMxNzYxZjFkM2M0Cg== --from-literal=osidb_url=myurl
