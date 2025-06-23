#!/usr/bin/env bash

# This file was created with assistance from the AI tool Cursor

set -euo pipefail

fail=0

echo Checking that computeResources are properly set for all steps in each modified managed or internal task

for file in ${CHANGED_FILES}; do
  # Only process non test files in tasks/managed and tasks/internal
  if [[ "$file" == */tests/* ]] || [[ ! "$file" =~ ^tasks/(managed|internal)/ ]]; then
    continue
  fi

  step_count=$(yq '.spec.steps | length' "$file")
  for ((i=0; i<step_count; i++)); do

    compute_resources=$(yq ".spec.steps[$i].computeResources" "$file")
    step_name=$(yq ".spec.steps[$i].name" "$file")

    if [[ "$compute_resources" == "null" ]]; then
      echo "ERROR: $file step $step_name (index $i) does not have computeResources defined"
      fail=1
      continue
    fi

    # Extract limits and requests for this step
    limits=$(yq '.limits' <<< "$compute_resources")
    requests=$(yq '.requests' <<< "$compute_resources")

    # Ensure limits.cpu is not defined
    if yq -e 'has("cpu")' <<< "$limits" > /dev/null 2>&1; then
      echo "ERROR: $file step $step_name (index $i) has limits.cpu defined. This should not be set"
      fail=1
    fi

    # Ensure requests.cpu is defined
    if ! yq -e 'has("cpu")' <<< "$requests" > /dev/null 2>&1; then
      echo "ERROR: $file step $step_name (index $i) does not have requests.cpu defined"
      fail=1
    fi

    # Ensure limits.memory equals requests.memory
    limits_mem=$(yq '.memory' <<< "$limits")
    requests_mem=$(yq '.memory' <<< "$requests")
    if [[ "$limits_mem" == "null" || "$requests_mem" == "null" || "$limits_mem" != "$requests_mem" ]]; then
      echo "ERROR: $file step $step_name (index $i) limits.memory and requests.memory must be defined and equal"
      fail=1
    fi

    # Check no other keys exist in computeResources (order-agnostic)
    if ! yq -e 'keys | contains(["limits","requests"]) and length == 2' <<< "$compute_resources" > /dev/null 2>&1; then
      echo "ERROR: $file step $step_name (index $i) computeResources has extra or missing keys"
      fail=1
    else
      # Check that limits only has memory and requests only has cpu and memory (order-agnostic)
      if ! yq -e 'keys | contains(["memory"]) and length == 1' <<< "$limits" > /dev/null 2>&1; then
        echo "ERROR: $file step $step_name (index $i) computeResources.limits has keys other than memory"
        fail=1
      fi
      if ! yq -e 'keys | contains(["cpu","memory"]) and length == 2' <<< "$requests" > /dev/null 2>&1; then
        echo "ERROR: $file step $step_name (index $i) computeResources.requests has keys other than cpu and memory"
        fail=1
      fi
    fi
  done
done

if [[ $fail -ne 0 ]]; then
  exit 1
fi
