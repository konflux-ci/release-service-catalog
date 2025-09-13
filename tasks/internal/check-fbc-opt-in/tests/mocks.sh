#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function kinit() {
  echo "Mock kinit called with: $*"
  echo $* >> /var/workdir/mock_kinit.txt
  # Mock successful kinit
  return 0
}
function curl() {
  echo "Mock curl called with: $*"
  echo $* >> /var/workdir/mock_curl.txt

  # Extract output file from curl arguments
  local output_file=""
  for ((i=1; i<=$#; i++)); do
    if [[ "${!i}" == "-o" ]]; then
      ((i++))
      output_file="${!i}"
      break
    fi
  done

  # Return mock Pyxis response with fbc_opt_in=true
  if [ -n "$output_file" ]; then
    cat > "$output_file" << 'EOF'
{
  "fbc_opt_in": true,
  "registry": "registry.io",
  "repository": "test-image1",
  "name": "tag1"
}
EOF
  fi

  # Mock successful curl
  return 0
}

# Export functions so they're available to the task scripts
export -f curl kinit
