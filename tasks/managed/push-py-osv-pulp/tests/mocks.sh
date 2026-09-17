#!/usr/bin/env bash
set -eux

# Mock: pulp — for `file content upload`, validate the required flags/env,
# validate that credentials are actually passed to the CLI via a --config
# cli.toml (pulp-cli does not read PULP_USERNAME/PULP_PASSWORD env vars), and
# drop the marker file the test checks instead of hitting a real Pulp server.
pulp() {
  echo "Mock pulp called: $*"
  : "${PULP_URL:?pulp url not set}"
  : "${PULP_DOMAIN:?pulp domain not set}"
  : "${PULP_FILE_REPOSITORY:?file repo not set}"
  test -f /etc/service-account-secret/username
  test -f /etc/service-account-secret/password

  local repo=""
  local config=""
  local prev=""
  for a in "$@"; do
    if [ "$prev" = "--repository" ]; then repo="$a"; fi
    if [ "$prev" = "--config" ]; then config="$a"; fi
    prev="$a"
  done

  if [ "$repo" != "${PULP_FILE_REPOSITORY}" ]; then
    echo "ERROR: --repository ($repo) does not match PULP_FILE_REPOSITORY (${PULP_FILE_REPOSITORY})"
    exit 1
  fi

  # pulp-cli does not read PULP_USERNAME/PULP_PASSWORD env vars (plain
  # click.option with no envvar= binding). Credentials must be passed via
  # --config <cli.toml> (or explicit --username/--password flags). Fail the
  # mock if neither reached the command line, so a regression back to
  # env-var-only auth is caught here instead of failing silently against a
  # real Pulp server.
  if [ -z "${config}" ]; then
    echo "ERROR: pulp invoked without --config; credentials would not reach pulp-cli"
    exit 1
  fi

  if [ ! -f "${config}" ]; then
    echo "ERROR: --config file not found: ${config}"
    exit 1
  fi

  if ! grep -q '^username = "test-user"$' "${config}" || ! grep -q '^password = "test-password"$' "${config}"; then
    echo "ERROR: --config file does not contain the expected credentials"
    cat "${config}"
    exit 1
  fi

  echo "osv_uploaded" > "${SECURITY_METADATA_DIR}/.osv_upload_marker"
}
export -f pulp
