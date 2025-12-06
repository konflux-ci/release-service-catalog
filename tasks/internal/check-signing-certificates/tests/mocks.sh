#!/usr/bin/env bash

function check_cert_expiration() {
  local cert_file="$1"
  echo "Mock check_cert_expiration called with: $cert_file"
  # Mock: always return success (certificate is valid)
  echo "Certificate $cert_file is valid (mocked)"
  return 0
}

