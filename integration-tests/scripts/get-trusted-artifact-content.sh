#!/usr/bin/env bash

#
# get-trusted-artifact-content.sh
#
# Fetch and extract content from a trusted artifact produced by a Tekton task.
#
# This script retrieves the sourceDataArtifact result from a TaskRun within a
# PipelineRun, then uses oras to fetch and extract the artifact content.
#
# Parameters:
#   $1: pipelinerun-name  - Name of the PipelineRun
#   $2: task-name         - Name of the task in the Pipeline
#   $3: result-name       - Name of the result containing the artifact URI (default: sourceDataArtifact)
#   $4: namespace         - Kubernetes namespace
#   $5: output-dir        - Directory to extract the artifact content to
#
# Environment Variables:
#   KUBECONFIG (optional) - Path to the kubeconfig file
#

set -euo pipefail

log() {
    echo "$@" >&2
}

error_exit() {
    log "🔴 Error: $1"
    exit 1
}

usage() {
    log "Usage: $0 <pipelinerun-name> <task-name> <result-name> <namespace> <output-dir>"
    log ""
    log "  pipelinerun-name: Name of the PipelineRun CR"
    log "  task-name:        Name of the task in the Pipeline"
    log "  result-name:      Name of the result (default: sourceDataArtifact)"
    log "  namespace:        Kubernetes namespace"
    log "  output-dir:       Directory to extract artifact content to"
    log ""
    log "Example: $0 my-pipeline-run push-rpms-to-pulp sourceDataArtifact my-namespace /tmp/output"
    exit 1
}

if [ $# -lt 5 ]; then
    usage
fi

PLR_NAME="$1"
TASK_NAME="$2"
RESULT_NAME="${3:-sourceDataArtifact}"
NAMESPACE="$4"
OUTPUT_DIR="$5"

log "Fetching trusted artifact from PipelineRun '${PLR_NAME}', task '${TASK_NAME}', result '${RESULT_NAME}'"

# Get the TaskRun name for the specified task
TASKRUN_NAME=$(kubectl get pipelinerun "$PLR_NAME" -n "$NAMESPACE" -o json | \
    jq -r --arg task_name "$TASK_NAME" '
        .status.childReferences[]? // .status.taskRuns // empty |
        select(.pipelineTaskName == $task_name) | .name
    ')

if [ -z "$TASKRUN_NAME" ]; then
    error_exit "Could not find TaskRun for task '$TASK_NAME' in PipelineRun '$PLR_NAME'"
fi

log "Found TaskRun: $TASKRUN_NAME"

# Get the result value from the TaskRun
ARTIFACT_URI=$(kubectl get taskrun "$TASKRUN_NAME" -n "$NAMESPACE" -o json | \
    jq -r --arg result_name "$RESULT_NAME" '
        .status.results[]? | select(.name == $result_name) | .value
    ')

if [ -z "$ARTIFACT_URI" ] || [ "$ARTIFACT_URI" == "null" ]; then
    log "Available results in TaskRun:"
    kubectl get taskrun "$TASKRUN_NAME" -n "$NAMESPACE" -o json | \
        jq -r '.status.results[]? | "  - " + .name' >&2
    error_exit "Could not find result '$RESULT_NAME' in TaskRun '$TASKRUN_NAME'"
fi

log "Found artifact URI: $ARTIFACT_URI"

# The artifact URI format is: registry/repo@sha256:hash
# Extract the OCI reference (remove any prefix like "oci:" if present)
OCI_REF="${ARTIFACT_URI#*:}"
if [[ "$ARTIFACT_URI" != *"@sha256:"* ]]; then
    # If no sha256, use as-is
    OCI_REF="$ARTIFACT_URI"
fi

log "OCI reference: $OCI_REF"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Check if oras is available
if ! command -v oras &> /dev/null; then
    error_exit "oras command not found. Please install oras to fetch the artifact."
fi

# Fetch and extract the artifact
# Trusted artifacts are stored as blobs, need to fetch the blob
log "Fetching artifact with oras..."

# Try to pull the artifact - trusted artifacts use a specific format
# First, try oras blob fetch (for single blob artifacts)
if oras blob fetch "$OCI_REF" --output - 2>/dev/null | tar -C "$OUTPUT_DIR" --no-overwrite-dir -zxmf - 2>/dev/null; then
    log "✅ Extracted artifact using oras blob fetch"
else
    # Fallback: try oras pull (for manifest-based artifacts)
    log "Trying oras pull..."
    if oras pull "$OCI_REF" -o "$OUTPUT_DIR" 2>/dev/null; then
        log "✅ Extracted artifact using oras pull"
    else
        error_exit "Failed to fetch artifact from $OCI_REF"
    fi
fi

log "✅ Artifact content extracted to: $OUTPUT_DIR"

# List contents for debugging
log "Contents:"
ls -la "$OUTPUT_DIR" >&2 || true

echo "$OUTPUT_DIR"
