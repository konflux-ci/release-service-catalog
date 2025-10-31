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

  # PURL performance test with many affected components
  if [[ "$*" == *"myurl/osidb/api/v1/flaws?cve_id=CVE-many-components"* ]]
  then
    # General impact is MODERATE, but target-repo component should have CRITICAL impact
    # Generate 500 affected components to test performance optimization
    echo -n '{"results": [{"impact": "MODERATE", "affects": ['
    
    for i in $(seq 1 500); do
      if [[ $i -eq 499 ]]; then
        # Put target-repo near the end with CRITICAL impact - forces processing of 498 components first
        echo -n '{"purl": "pkg:oci/comp'$i'?repository_url=target-repo&v=1", "impact": "CRITICAL"}'
      else
        # Alternate between LOW and MODERATE for other components
        if [[ $((i % 2)) -eq 0 ]]; then
          impact="MODERATE"
        else
          impact="LOW"
        fi
        echo -n '{"purl": "pkg:oci/comp'$i'?repository_url=repo'$i'&v=1", "impact": "'$impact'"}'
      fi
      
      # Add comma except for last element
      if [[ $i -lt 500 ]]; then
        echo -n ','
      fi
    done
    
    echo ']}]}'
  elif [[ "$*" == *"myurl/osidb/api/v1/flaws?cve_id=CVE-critical"* ]]
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
