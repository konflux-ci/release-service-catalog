#!/bin/bash

set -e

DEFAULT_REPOSITORIES="source,x86_64,s390x,ppc64le,aarch64"

usage() {
  cat <<EOF
Usage: $(basename "$0") --domain <domain> [OPTIONS]

Create Pulp domain, repositories, and distributions.

Required:
  --domain <name>      Pulp domain name to create/use

Optional:
  --repos <list>       Comma-separated repository names
                       Default: ${DEFAULT_REPOSITORIES}
  --config <path>      Path to pulp CLI config file (e.g., ci.toml)
  --help               Show this help message

Examples:
  $(basename "$0") --domain my-domain
  $(basename "$0") --domain my-domain --repos "repo1,repo2"
  $(basename "$0") --domain my-domain --config /path/to/config.toml
  $(basename "$0") --domain my-domain --repos "repo1,repo2" --config /path/to/config.toml
EOF
  exit "${1:-0}"
}

PULP_DOMAIN=""
PULP_REPOSITORIES_STRING=""
PULP_CONFIG_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      PULP_DOMAIN="$2"
      shift 2
      ;;
    --repos)
      PULP_REPOSITORIES_STRING="$2"
      shift 2
      ;;
    --config)
      PULP_CONFIG_FILE="$2"
      shift 2
      ;;
    --help)
      usage 0
      ;;
    *)
      echo "🔴 Unknown option: $1"
      usage 1
      ;;
  esac
done

if [[ -z "${PULP_DOMAIN}" ]]; then
  echo "🔴 error: --domain is required"
  usage 1
fi

if [[ -n "${PULP_REPOSITORIES_STRING}" ]]; then
  echo "ℹ️ Using provided repositories: ${PULP_REPOSITORIES_STRING}"
else
  PULP_REPOSITORIES_STRING="${DEFAULT_REPOSITORIES}"
  echo "ℹ️ Using default repositories: ${PULP_REPOSITORIES_STRING}"
fi

PULP_CONFIG_OPT=()
if [[ -n "${PULP_CONFIG_FILE}" ]]; then
  PULP_CONFIG_OPT=(--config "${PULP_CONFIG_FILE}")
  echo "ℹ️ Using pulp config file: ${PULP_CONFIG_FILE}"
fi

# Parse comma-delimited string into array
IFS=',' read -ra PULP_REPOSITORIES <<< "${PULP_REPOSITORIES_STRING}"

# Remove leading/trailing whitespace from each repository name
for i in "${!PULP_REPOSITORIES[@]}"; do
  PULP_REPOSITORIES[i]=$(echo "${PULP_REPOSITORIES[i]}" | xargs)
done

echo "ℹ️ Will create repositories: ${PULP_REPOSITORIES[*]}"

# Check domain existence robustly (avoids pagination/truncation)
if pulp "${PULP_CONFIG_OPT[@]}" domain show --name "${PULP_DOMAIN}" >/dev/null 2>&1; then
  echo "ℹ️ Domain '${PULP_DOMAIN}' already exists. Skipping creation."
else
  echo "🆕 Domain '${PULP_DOMAIN}' not found. Creating..."
  # Attempt creation; if it already exists, report and continue
  if ! pulp "${PULP_CONFIG_OPT[@]}" console populated-domain create --name "${PULP_DOMAIN}" >/dev/null 2>&1; then
    echo "⚠️  Domain creation reported an error; verifying existence..."
    if ! pulp "${PULP_CONFIG_OPT[@]}" domain show --name "${PULP_DOMAIN}" >/dev/null 2>&1; then
      echo "🔴 Error: Failed to create domain '${PULP_DOMAIN}' and it does not exist."
      exit 1
    fi
    echo "ℹ️ Domain '${PULP_DOMAIN}' now exists. Continuing."
  fi
fi

# Create repositories
for PULP_REPOSITORY in "${PULP_REPOSITORIES[@]}"; do
    echo "🔄 Processing repository: ${PULP_REPOSITORY}"

    if pulp "${PULP_CONFIG_OPT[@]}" --domain "${PULP_DOMAIN}" rpm repository show --name "${PULP_REPOSITORY}" >/dev/null 2>&1; then
      echo "ℹ️ Repository '${PULP_REPOSITORY}' already exists. Skipping creation."
    else
      echo "🆕 Repository '${PULP_REPOSITORY}' not found. Creating..."
      pulp "${PULP_CONFIG_OPT[@]}" --domain "${PULP_DOMAIN}" rpm repository create --name "${PULP_REPOSITORY}"
      pulp "${PULP_CONFIG_OPT[@]}" --domain "${PULP_DOMAIN}" rpm repository update --name "${PULP_REPOSITORY}" --autopublish
    fi
    # Ensure distribution exists (recreate if it was deleted)
    if pulp "${PULP_CONFIG_OPT[@]}" --domain "${PULP_DOMAIN}" rpm distribution show --name "${PULP_REPOSITORY}" >/dev/null 2>&1; then
      echo "ℹ️ Distribution '${PULP_REPOSITORY}' already exists. Skipping creation."
    else
      echo "🆕 Distribution '${PULP_REPOSITORY}' not found. Creating..."
      pulp "${PULP_CONFIG_OPT[@]}" --domain "${PULP_DOMAIN}" rpm distribution create \
        --name "${PULP_REPOSITORY}" \
        --repository "${PULP_REPOSITORY}" \
        --base-path "${PULP_REPOSITORY}"
    fi
done
echo "✅ Setup complete."
