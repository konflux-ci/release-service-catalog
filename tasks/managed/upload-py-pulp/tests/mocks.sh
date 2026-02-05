#!/usr/bin/env bash
set -eux

# Mock pulp-upload script
echo "Mock pulp-upload called"
echo "PULP_BASE_URL: ${PULP_BASE_URL}"
echo "PULP_API_ROOT: ${PULP_API_ROOT}"
echo "PULP_DOMAIN: ${PULP_DOMAIN}"
echo "PULP_REPOSITORY: ${PULP_REPOSITORY}"
echo "FILES_DIR: ${FILES_DIR}"

# Check that required environment variables are set
if [ -z "${PULP_BASE_URL:-}" ]; then
  echo "ERROR: PULP_BASE_URL not set"
  exit 1
fi

if [ -z "${PULP_DOMAIN:-}" ]; then
  echo "ERROR: PULP_DOMAIN not set"
  exit 1
fi

if [ -z "${PULP_REPOSITORY:-}" ]; then
  echo "ERROR: PULP_REPOSITORY not set"
  exit 1
fi

# Check that service account secret is mounted
if [ ! -f /etc/service-account-secret/username ]; then
  echo "ERROR: Service account username not found"
  exit 1
fi

if [ ! -f /etc/service-account-secret/password ]; then
  echo "ERROR: Service account password not found"
  exit 1
fi

# Check that files exist
if [ ! -d "${FILES_DIR}" ]; then
  echo "ERROR: FILES_DIR does not exist: ${FILES_DIR}"
  exit 1
fi

echo "Files to upload:"
ls -la "${FILES_DIR}"

# Create a marker file to indicate upload was called
echo "upload_called" > "${FILES_DIR}/.upload_marker"

echo "Mock pulp-upload completed successfully"

