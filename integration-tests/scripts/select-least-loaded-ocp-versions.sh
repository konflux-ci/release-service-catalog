#!/usr/bin/env bash
#
# Summary:
#   Picks an OCP version for each of the 6 fbc-release OCP_VER slots, steering
#   the run's IIB requests to the least-loaded IIB queues, and prints the 6
#   versions in slot order, one per line.
#
#   IIB runs the builds of each serial queue one at a time, and several
#   versions share a queue, so a version is scored by its queue's load:
#     - in-progress IIB builds of the queue's versions. IIB is not reachable
#       from the e2e cluster, so they come from the get-iib-builds-load
#       internal pipeline through an InternalRequest in the managed namespace;
#     - plus "pending" builds: Components other fbc-release runs created in the
#       last IIB_PENDING_WINDOW_MINUTES, whose builds haven't reached IIB yet.
#       Runs that start together can't see each other in IIB, only here;
#     - plus IIB_DEFAULT_QUEUE_PENALTY on IIB_DEFAULT_QUEUE, which also serves
#       indexes we don't count.
#
#   The slots this run uses are filled busiest first, each with a different
#   version on a different queue while queues last (so a multi-component pair
#   never shares a version, and doesn't share a queue either), choosing at
#   random among queues within 1 of the lightest so concurrent runs spread out.
#   Unused slots get the remaining versions. If the IIB loads can't be fetched,
#   only the pending builds steer the pick.
#
# Parameters:
#   $1:  weights  - Comma-separated IIB request count per slot, 6 values; 0 = slot unused.
#   $2+: versions - Candidate OCP versions (e.g. 4.13 4.14 ...), at least 6.
#
# Environment Variables:
#   managed_namespace             - Namespace to create the InternalRequest in.
#   RELEASE_CATALOG_GIT_URL       - Catalog git URL the internal pipeline is resolved from.
#   RELEASE_CATALOG_GIT_REVISION  - Catalog git revision the internal pipeline is resolved from.
#   IIB_BUILDS_USER               - IIB user whose in-progress builds are counted.
#   IIB_QUEUES                    - Space-separated <version>=<queue> pairs.
#   IIB_DEFAULT_QUEUE             - Queue of versions missing from IIB_QUEUES. Optional;
#                                   without it each unmapped version is its own queue.
#   IIB_DEFAULT_QUEUE_PENALTY     - Extra load on IIB_DEFAULT_QUEUE. Optional, defaults to 0.
#   tenant_namespace              - Namespace of the fbc-release Components. Optional;
#   originating_tool              - and their originating-tool label. Without both, no
#                                   pending builds are counted.
#   IIB_PENDING_WINDOW_MINUTES    - Age up to which a Component counts as pending. Optional,
#                                   defaults to 60.
#   IIB_LOAD_TIMEOUT              - Seconds to wait for the InternalRequest. Optional, defaults to 300.
#
# Dependencies:
#   kubectl, jq

set -euo pipefail

weights_arg="${1:?usage: $0 <weights> <version>...}"
shift
: "${managed_namespace:?missing env var managed_namespace}"
: "${RELEASE_CATALOG_GIT_URL:?missing env var RELEASE_CATALOG_GIT_URL}"
: "${RELEASE_CATALOG_GIT_REVISION:?missing env var RELEASE_CATALOG_GIT_REVISION}"
: "${IIB_BUILDS_USER:?missing env var IIB_BUILDS_USER}"

IFS=, read -r -a weights <<< "${weights_arg}"
if [ "${#weights[@]}" -ne 6 ] || [[ ! "${weights_arg}" =~ ^[0-9]+(,[0-9]+){5}$ ]]; then
  echo "error: weights must be 6 comma-separated numbers, got '${weights_arg}'" >&2
  exit 1
fi
versions=("$@")
if [ "${#versions[@]}" -lt 6 ]; then
  echo "error: need at least 6 versions, got ${#versions[@]}" >&2
  exit 1
fi

FROM_INDEX_PREFIX="registry-proxy.engineering.redhat.com/rh-osbs/iib-preview-rhtap:v"
# A version whose IIB load can't be fetched (while others can) scores after every
# version with a known load, so a failed lookup is never mistaken for an idle one.
UNKNOWN_LOAD=999999

# Prints the loads JSON ({"<from_index>": <count>}), or fails. It runs in an
# `if !` context, where set -e is off, so every step checks its own status.
get_loads() {
  local from_indexes payload request status loads
  from_indexes=$(jq -cn --arg p "${FROM_INDEX_PREFIX}" '$ARGS.positional | map($p + .)' --args "$@")
  payload=$(jq -n \
    --arg url "${RELEASE_CATALOG_GIT_URL}" \
    --arg revision "${RELEASE_CATALOG_GIT_REVISION}" \
    --arg fromIndexes "${from_indexes}" \
    --arg user "${IIB_BUILDS_USER}" \
    '{
      apiVersion: "appstudio.redhat.com/v1alpha1",
      kind: "InternalRequest",
      metadata: {generateName: "get-iib-builds-load-"},
      spec: {
        pipeline: {
          pipelineRef: {
            resolver: "git",
            params: [
              {name: "url", value: $url},
              {name: "revision", value: $revision},
              {name: "pathInRepo", value: "pipelines/internal/get-iib-builds-load/get-iib-builds-load.yaml"}
            ]
          }
        },
        params: {fromIndexes: $fromIndexes, user: $user, taskGitUrl: $url, taskGitRevision: $revision},
        timeouts: {pipeline: "0h5m0s", tasks: "0h4m0s", finally: "0h1m0s"}
      }
    }')
  request=$(kubectl create -n "${managed_namespace}" -f - -o jsonpath='{.metadata.name}' <<< "${payload}") || return 1
  echo "Internal request created: ${request}" >&2
  # The results are read below, so the request isn't needed after this script.
  trap 'kubectl delete internalrequest -n "${managed_namespace}" "${request}" --ignore-not-found >/dev/null 2>&1 || true' RETURN

  # While the pipeline runs, Succeeded is False with reason Running; the request
  # has completed once it's True, or False with any other reason.
  for ((waited = 0; waited < ${IIB_LOAD_TIMEOUT:-300}; waited += 5)); do
    condition=$(kubectl get internalrequest -n "${managed_namespace}" "${request}" -o jsonpath=\
'{.status.conditions[?(@.type=="Succeeded")].status}/{.status.conditions[?(@.type=="Succeeded")].reason}') \
      || condition=""
    status="${condition%%/*}"
    case "${condition}" in
      False/Running) ;;
      True/*|False/*)
        results=$(kubectl get internalrequest -n "${managed_namespace}" "${request}" \
          -o jsonpath='{.status.results}') || results=""
        echo "Internal request results: ${results}" >&2
        if [ "${status}" = False ]; then
          echo "Internal request ${request} failed: $(kubectl get internalrequest -n "${managed_namespace}" \
            "${request}" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].message}')" >&2
          return 1
        fi
        loads=$(jq -r '.loads // empty' <<< "${results}" 2>/dev/null) || return 1
        jq -e 'type == "object"' <<< "${loads}" >/dev/null 2>&1 || return 1
        echo "${loads}"
        return 0
        ;;
    esac
    sleep 5
  done
  echo "Timed out waiting for internal request ${request}" >&2
  return 1
}

# Prints the OCP version of each Component other fbc-release runs created in the
# pending window, one per line (one Component = one IIB request). Its builds may
# already be in IIB near the end of the window; counting them twice for a while
# only makes a busy queue look busier.
get_pending() {
  [ -n "${tenant_namespace:-}" ] && [ -n "${originating_tool:-}" ] || return 0
  kubectl get components -n "${tenant_namespace}" -l "originating-tool=${originating_tool}" -o json \
    | jq -r --argjson window "$(( ${IIB_PENDING_WINDOW_MINUTES:-60} * 60 ))" '
        .items[]
        | select(now - (.metadata.creationTimestamp | fromdateiso8601) < $window)
        | (.spec.source.git.context // "" | capture("v(?<v>[0-9]+\\.[0-9]+)").v)? // empty'
}

declare -A queue_of iib pending qload
for pair in ${IIB_QUEUES:-}; do
  queue_of["${pair%%=*}"]="${pair#*=}"
done
queue_for() {
  echo "${queue_of[$1]:-${IIB_DEFAULT_QUEUE:-v$1}}"
}

iib_ok=true
if ! loads=$(get_loads "${versions[@]}"); then
  echo "⚠️  Could not get the IIB loads, picking by pending builds only" >&2
  iib_ok=false
fi
if ! pending_versions=$(get_pending); then
  echo "⚠️  Could not list pending fbc-release Components, ignoring them" >&2
  pending_versions=""
fi

for v in "${versions[@]}"; do
  pending[$v]=$(grep -cxF "${v}" <<< "${pending_versions}" || true)
  if ${iib_ok}; then
    iib[$v]=$(jq -r --arg i "${FROM_INDEX_PREFIX}${v}" '.[$i] // "unknown"' <<< "${loads}")
  else
    iib[$v]=0
  fi
  q=$(queue_for "${v}")
  [ "${iib[$v]}" = unknown ] || qload[$q]=$(( ${qload[$q]:-0} + iib[$v] ))
  qload[$q]=$(( ${qload[$q]:-0} + pending[$v] ))
done
if [ -n "${IIB_DEFAULT_QUEUE:-}" ] && [ -n "${qload[${IIB_DEFAULT_QUEUE}]+x}" ]; then
  qload[${IIB_DEFAULT_QUEUE}]=$(( qload[${IIB_DEFAULT_QUEUE}] + ${IIB_DEFAULT_QUEUE_PENALTY:-0} ))
fi

score() {
  local q
  q=$(queue_for "$1")
  if [ "${iib[$1]}" = unknown ]; then
    echo $(( qload[$q] + UNKNOWN_LOAD ))
  else
    echo "${qload[$q]}"
  fi
}

echo "IIB queue loads (in progress + pending + penalty):" >&2
for q in $(printf '%s\n' "${!qload[@]}" | sort); do
  members=""
  for v in "${versions[@]}"; do
    if [ "$(queue_for "${v}")" = "${q}" ]; then members+="v${v}=${iib[$v]}+${pending[$v]} "; fi
  done
  echo "  ${q}: ${qload[$q]}  (${members% })" >&2
done

declare -A used_version used_queue picked
# Slots this run uses, busiest first, ties by slot number.
for slot in $(for i in "${!weights[@]}"; do [ "${weights[$i]}" -gt 0 ] && echo "${weights[$i]} ${i}"; done \
    | sort -k1,1nr -k2,2n | cut -d' ' -f2); do
  candidates=()
  for v in "${versions[@]}"; do
    if [ -z "${used_version[$v]+x}" ] && [ -z "${used_queue[$(queue_for "${v}")]+x}" ]; then candidates+=("${v}"); fi
  done
  # More slots than queues: share a queue, but never a version.
  if [ "${#candidates[@]}" -eq 0 ]; then
    for v in "${versions[@]}"; do if [ -z "${used_version[$v]+x}" ]; then candidates+=("${v}"); fi; done
  fi
  best=$(for v in "${candidates[@]}"; do score "${v}"; done | sort -n | head -1)
  near=()
  for v in "${candidates[@]}"; do if [ "$(score "${v}")" -le $(( best + 1 )) ]; then near+=("${v}"); fi; done
  v="${near[RANDOM % ${#near[@]}]}"
  q=$(queue_for "${v}")
  picked[$slot]="${v}"
  used_version[$v]=1
  used_queue[$q]=1
  # The rest of this run sees its own requests on that queue.
  qload[$q]=$(( qload[$q] + weights[slot] ))
  echo "Slot ${slot} (${weights[$slot]} IIB request(s)): v${v} on ${q}" >&2
done

# Unused slots: the remaining versions, lightest first.
mapfile -t rest < <(for v in "${versions[@]}"; do
  [ -z "${used_version[$v]+x}" ] && echo "$(score "${v}") ${RANDOM} ${v}"
done | sort -n -k1,1 -k2,2 | cut -d' ' -f3)
for slot in 0 1 2 3 4 5; do
  if [ -z "${picked[$slot]+x}" ]; then
    picked[$slot]="${rest[0]}"
    rest=("${rest[@]:1}")
  fi
  echo "${picked[$slot]}"
done
