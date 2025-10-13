#!/usr/bin/env bash

set -euo pipefail

fail=0

echo "Checking that secrets are not mounted as variables for all steps and stepTemplates in each modified managed or internal task"

for file in ${CHANGED_FILES}; do
  # Only process non test files in tasks/managed and tasks/internal
  if [[ "$file" == */tests/* ]] || [[ ! "$file" =~ ^tasks/(managed|internal)/ ]]; then
    continue
  fi

  # Check steps
  step_count=$(yq '.spec.steps | length' "$file" 2>/dev/null || echo 0)
  if [[ "$step_count" != "null" && "$step_count" -gt 0 ]]; then
    for ((i=0; i<step_count; i++)); do
      env_count=$(yq ".spec.steps[$i].env | length" "$file" 2>/dev/null || echo 0)
      step_name=$(yq ".spec.steps[$i].name" "$file" 2>/dev/null || echo "")
      if [[ "$env_count" == "null" || "$env_count" -eq 0 ]]; then
        continue
      fi
      for ((j=0; j<env_count; j++)); do
        secret_name=$(yq ".spec.steps[$i].env[$j].valueFrom.secretKeyRef.name" "$file" 2>/dev/null || echo "null")
        env_name=$(yq ".spec.steps[$i].env[$j].name" "$file" 2>/dev/null || echo "")
        if [[ "$secret_name" != "null" ]]; then
          echo "ERROR: $file step $step_name (index $i) has secret '$secret_name' mounted as variable '\$${env_name}'"
          fail=1
        fi
      done
    done
  fi

  # Check stepTemplate
  # .spec.stepTemplate is usually an object
  if yq '.spec.stepTemplate' "$file" 2>/dev/null | grep -vq '^null$'; then
    env_count=$(yq '.spec.stepTemplate.env | length' "$file" 2>/dev/null || echo 0)
    step_name=$(yq '.spec.stepTemplate.name' "$file" 2>/dev/null || echo "stepTemplate")
    if [[ "$env_count" != "null" && "$env_count" -gt 0 ]]; then
      for ((j=0; j<env_count; j++)); do
        secret_name=$(yq ".spec.stepTemplate.env[$j].valueFrom.secretKeyRef.name" "$file" 2>/dev/null || echo "null")
        env_name=$(yq ".spec.stepTemplate.env[$j].name" "$file" 2>/dev/null || echo "")
        if [[ "$secret_name" != "null" ]]; then
          echo "ERROR: $file stepTemplate (env index $j) has secret '$secret_name' mounted as variable '\$${env_name}'"
          fail=1
        fi
      done
    fi
  fi

  # Check sidecars
  sidecar_count=$(yq '.spec.sidecars | length' "$file" 2>/dev/null || echo 0)
  if [[ "$sidecar_count" != "null" && "$sidecar_count" -gt 0 ]]; then
    for ((i=0; i<sidecar_count; i++)); do
      env_count=$(yq ".spec.sidecars[$i].env | length" "$file" 2>/dev/null || echo 0)
      sidecar_name=$(yq ".spec.sidecars[$i].name" "$file" 2>/dev/null || echo "")
      if [[ "$env_count" == "null" || "$env_count" -eq 0 ]]; then
        continue
      fi
      for ((j=0; j<env_count; j++)); do
        secret_name=$(yq ".spec.sidecars[$i].env[$j].valueFrom.secretKeyRef.name" "$file" 2>/dev/null || echo "null")
        env_name=$(yq ".spec.sidecars[$i].env[$j].name" "$file" 2>/dev/null || echo "")
        if [[ "$secret_name" != "null" ]]; then
          echo "ERROR: $file sidecar $sidecar_name (index $i) has secret '$secret_name' mounted as variable '\$${env_name}'"
          fail=1
        fi
      done
    done
  fi
done

if [[ $fail -ne 0 ]]; then
  exit 1
fi
