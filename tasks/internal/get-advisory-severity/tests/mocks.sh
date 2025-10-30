#!/usr/bin/env sh
set -exo pipefail

# mocks to be injected into task step scripts

function kinit() {
  echo "kinit $*"
}

function curl() {
  echo Mock curl called with: $* >&2

  if [[ "$*" == "--retry 3 --negotiate -u : myurl/auth/token" ]]
  then
    sleep 0.1  # Small delay to simulate network
    echo '{"access": "batch-token-'${RANDOM}'"}'
    return
  fi

  # Performance test CVE requests - simulate realistic API delay
  if [[ "$*" == *"myurl/osidb/api/v1/flaws?cve_id=CVE-"*[0-9]* ]]
  then
    sleep 0.2  # Simulate 200ms API response time
    
    # Extract CVE number for response variety
    cve_id=$(echo "$*" | grep -o 'CVE-[0-9]*')
    if [[ "$cve_id" =~ CVE-([0-9]+) ]]; then
      cve_num="${BASH_REMATCH[1]}"
      
      # Make every 10th CVE critical, rest moderate
      if [[ $((cve_num % 10)) -eq 0 ]]; then
        echo '{"results": [{"impact":"CRITICAL","affects":[]}]}'
      else
        echo '{"results": [{"impact":"MODERATE","affects":[]}]}'
      fi
    fi
    return
  fi

  # Non numerical CVEs aren't part of performance tests, so do not include a sleep
  if [[ "$*" == *"myurl/osidb/api/v1/flaws?cve_id=CVE-critical"* ]]
  then
    echo '{"results": [{"impact":"CRITICAL","affects":[{"purl":"pkg:oci/kubernetes?repository_url=component&a=b","impact":""}]}]}'
  elif [[ "$*" == *"myurl/osidb/api/v1/flaws?cve_id=CVE-moderate"* ]]
  then
    echo '{"results": [{"impact":"MODERATE","affects":[{"purl":"pkg:oci/kubernetes?repository_url=foo&a=b","impact":"LOW"},{"purl":"pkg:oci/kubernetes?repository_url=component&a=b","impact":"IMPORTANT"},{"purl":"","impact":"LOW"}]}]}'
  else
    echo Error: Unexpected call
    exit 1
  fi
}

# The retry script won't see the kinit function unless we export it
export -f kinit
