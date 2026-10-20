#!/usr/bin/env bash
set -euo pipefail

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Create the dummy secret required by the task's rok-access volume.
kubectl delete secret rok-storage --ignore-not-found
kubectl create secret generic rok-storage --from-literal=cert=mycert --from-literal=key=mykey
