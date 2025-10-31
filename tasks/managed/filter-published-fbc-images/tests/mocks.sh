# mocks to be injected into task step scripts
echo "==================================================================" >&2
echo "🔧 MOCKS.SH BEING LOADED - START OF INJECTION" >&2
echo "==================================================================" >&2

kubectl() {
  echo "Mock kubectl called with: $*" >&2

  # Mock kubectl get secret - simulate the pyxis secret exists
  if [[ "$*" == "get secret pyxis"* ]]; then
    return 0
  # Mock kubectl get secret -o json to extract cert/key
  elif [[ "$*" == "get secret pyxis -o json" ]]; then
    echo '{
      "data": {
        "cert": "'$(echo -n "mock-cert" | base64)'",
        "key": "'$(echo -n "mock-key" | base64)'"
      }
    }'
  else
    # For any other kubectl command, call the real kubectl
    command kubectl "$@"
  fi
}

skopeo() {
  echo "Mock skopeo called with: $*" >&2

  # Mock skopeo inspect to return OCP version in org.opencontainers.image.base.name
  if [[ "$*" == *"inspect"* ]]; then
    # Extract image digest from arguments to determine which OCP version to return
    local image=""
    for arg in "$@"; do
      if [[ "$arg" == docker://* ]]; then
        image="$arg"
        break
      fi
    done

    echo "Mock skopeo inspecting image: $image" >&2

    # Determine OCP version based on component image digest
    local ocp_version=""
    if [[ "$image" == *"@sha256:comp1v414"* ]] || [[ "$image" == *"@sha256:comp2v414"* ]]; then
      ocp_version="4.14"
    elif [[ "$image" == *"@sha256:comp3v416"* ]] || [[ "$image" == *"@sha256:comp4v416"* ]]; then
      ocp_version="4.16"
    else
      # Default OCP version for other tests (no 'v' prefix - template adds it)
      ocp_version="4.15"
    fi

    echo "Mock skopeo returning OCP version: $ocp_version for image: $image" >&2

    # Return mock skopeo inspect JSON with OCP version in base image annotation
    # Note: using both Labels and annotations to be compatible with different formats
    local json_output
    json_output=$(cat <<EOF
{
  "Name": "$image",
  "Digest": "sha256:mockdigest",
  "RepoTags": [],
  "Created": "2024-01-01T00:00:00Z",
  "DockerVersion": "",
  "Labels": {
    "org.opencontainers.image.base.name": "registry.access.redhat.com/ubi9/ubi:$ocp_version"
  },
  "Architecture": "amd64",
  "Os": "linux",
  "Layers": [],
  "Env": [],
  "annotations": {
    "org.opencontainers.image.base.name": "registry.access.redhat.com/ubi9/ubi:$ocp_version"
  }
}
EOF
)
    echo "$json_output"
    echo "📤 Skopeo mock returned JSON with OCP version: $ocp_version" >&2
    return 0
  else
    # For any other skopeo command, call the real skopeo
    command skopeo "$@"
  fi
}

curl() {
  echo "Mock curl called with: $*" >&2

  # Parse curl flags to extract output file (-o flag)
  output_file=""
  write_out=""
  local args=("$@")
  for ((i=0; i<${#args[@]}; i++)); do
    if [[ "${args[i]}" == "-o" ]]; then
      output_file="${args[i+1]}"
    elif [[ "${args[i]}" == "-w" ]]; then
      write_out="${args[i+1]}"
    fi
  done

  # Verify Phase 1 optimization parameters are present
  if [[ "$*" == *"v1/images?filter="* ]]; then
    # Verify date filter is present (last_update_date>=YYYY-MM-DD or URL-encoded %3E%3D)
    if [[ ! "$*" =~ last_update_date(%3E%3D|>=)[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
      echo "ERROR: Date filter (last_update_date) not found in Pyxis query" >&2
      return 1
    fi
    
    # Verify page_size parameter is present
    if [[ "$*" != *"page_size=500"* ]]; then
      echo "ERROR: page_size=500 parameter not found in Pyxis query" >&2
      return 1
    fi
    
    echo "✓ Verified: Date filter and page_size=500 present in query" >&2
  fi

  # Determine which JSON response to return based on query
  local json_response=""
  local http_status="200"
  
  # ERROR SCENARIOS (for gap coverage tests)
  
  # Pyxis 500 error test - simulate API server error
  if [[ "$*" == *"catalog-500-error"* ]]; then
    json_response='{"error": "Internal Server Error", "message": "Database connection failed"}'
    http_status="500"
  # Malformed JSON test - simulate corrupted response
  elif [[ "$*" == *"catalog-malformed"* ]]; then
    json_response='{"data": [{"_id": "broken", "malformed_json'
    http_status="200"
  
  # NORMAL SCENARIOS
  
  # Index with published fragments sha256:abc123 and sha256:ghi789
  # Match fully URL-encoded filter: docker_image_id==quay.io/redhat-pending/catalog:v4.14-published;last_update_date>=...
  elif [[ "$*" == *"docker_image_id%3D%3Dquay.io%2Fredhat-pending%2Fcatalog%3Av4.14-published%3Blast_update_date"* ]]; then
    json_response='{
      "data": [{
        "_id": "index-v4.14",
        "docker_image_digest": "sha256:index-v4.14-digest",
        "docker_image_id": "quay.io/redhat-pending/catalog:v4.14-published",
        "related_images": [
          {
            "image": "quay.io/test/comp1@sha256:abc123",
            "name": "comp1-bundle",
            "digest": "sha256:abc123"
          },
          {
            "image": "quay.io/test/comp3@sha256:ghi789",
            "name": "comp3-bundle",
            "digest": "sha256:ghi789"
          }
        ]
      }]
    }'
  # Index with NO published fragments (empty index or not yet published)
  elif [[ "$*" == *"docker_image_id%3D%3Dquay.io%2Fredhat-pending%2Fcatalog%3Av4.15-unpublished%3Blast_update_date"* ]]; then
    json_response='{"data": []}'
  # All fragments published - for all-published test
  elif [[ "$*" == *"docker_image_id%3D%3Dquay.io%2Fredhat-pending%2Fcatalog%3Av4.16-all-published%3Blast_update_date"* ]]; then
    json_response='{
      "data": [{
        "_id": "index-v4.16-all",
        "docker_image_digest": "sha256:index-v4.16-all-digest",
        "docker_image_id": "quay.io/redhat-pending/catalog:v4.16-all-published",
        "related_images": [
          {
            "image": "quay.io/test/comp1@sha256:mno345",
            "name": "comp1-bundle",
            "digest": "sha256:mno345"
          },
          {
            "image": "quay.io/test/comp2@sha256:pqr678",
            "name": "comp2-bundle",
            "digest": "sha256:pqr678"
          }
        ]
      }]
    }'
  # Empty response test - no index at all
  elif [[ "$*" == *"docker_image_id%3D%3Dquay.io%2Fredhat-pending%2Fcatalog%3Av4.17-empty%3Blast_update_date"* ]]; then
    json_response='{"data": []}'
  # Bundles field test - alternative structure with bundles instead of related_images
  elif [[ "$*" == *"docker_image_id%3D%3Dquay.io%2Fredhat-pending%2Fcatalog%3Av4.18-bundles%3Blast_update_date"* ]]; then
    json_response='{
      "data": [{
        "_id": "index-v4.18-bundles",
        "docker_image_digest": "sha256:index-v4.18-bundles-digest",
        "docker_image_id": "quay.io/redhat-pending/catalog:v4.18-bundles",
        "bundles": [
          {
            "bundle_path": "registry/bundle1",
            "csv_name": "bundle1-csv",
            "related_images": [
              {
                "image": "quay.io/test/bundle1@sha256:bun111",
                "name": "bundle1-image",
                "digest": "sha256:bun111"
              }
            ]
          },
          {
            "bundle_path": "registry/bundle2",
            "csv_name": "bundle2-csv",
            "related_images": [
              {
                "image": "quay.io/test/bundle2@sha256:bun222",
                "name": "bundle2-image",
                "digest": "sha256:bun222"
              }
            ]
          }
        ]
      }]
    }'
  # Multi-OCP test: v4.14 catalog with comp1v414 published (comp2v414 not published)
  elif [[ "$*" == *"docker_image_id%3D%3Dquay.io%2Fredhat-pending%2Fcatalog%3Av4.14%3Blast_update_date"* ]]; then
    echo "✅ Matched v4.14 catalog pattern - returning comp1v414 as published" >&2
    json_response='{
      "data": [{
        "_id": "index-v4.14-multi",
        "docker_image_digest": "sha256:index-v4.14-multi-digest",
        "docker_image_id": "quay.io/redhat-pending/catalog:v4.14",
        "related_images": [
          {
            "image": "quay.io/test/comp1@sha256:comp1v414",
            "name": "comp1-v414-bundle",
            "digest": "sha256:comp1v414"
          }
        ]
      }]
    }'
  # Multi-OCP test: v4.16 catalog with comp3v416 published (comp4v416 not published)
  elif [[ "$*" == *"docker_image_id%3D%3Dquay.io%2Fredhat-pending%2Fcatalog%3Av4.16%3Blast_update_date"* ]] && [[ "$*" != *"all-published"* ]]; then
    echo "✅ Matched v4.16 catalog pattern - returning comp3v416 as published" >&2
    json_response='{
      "data": [{
        "_id": "index-v4.16-multi",
        "docker_image_digest": "sha256:index-v4.16-multi-digest",
        "docker_image_id": "quay.io/redhat-pending/catalog:v4.16",
        "related_images": [
          {
            "image": "quay.io/test/comp3@sha256:comp3v416",
            "name": "comp3-v416-bundle",
            "digest": "sha256:comp3v416"
          }
        ]
      }]
    }'
  else
    # Default: return empty data (no published index)
    echo "⚠️  No curl pattern matched - returning empty data. Query was: $*" >&2
    json_response='{"data": []}'
  fi

  if [[ -n "$output_file" ]]; then
    # Write JSON to file (simulating -o flag)
    echo "$json_response" > "$output_file"
  else
    echo "$json_response"
  fi

  if [[ "$write_out" == "%{http_code}" ]]; then
    echo "$http_status"
  fi

  # Return appropriate exit code based on HTTP status
  if [[ "$http_status" == "500" ]]; then
    return 0  # curl itself succeeds, but HTTP status is 500
  fi
  
  return 0
}

# Export mock functions so they're available in subshells and when called by scripts
export -f kubectl
export -f skopeo
export -f curl

# CRITICAL FIX: Create wrapper executables in PATH to ensure mocks are called
# Bash functions don't work reliably in command substitutions $(...)
# Solution: Create executable mock scripts that will be found first in PATH
MOCK_BIN_DIR="/tmp/filter-fbc-mocks-$$"
mkdir -p "$MOCK_BIN_DIR"
export PATH="$MOCK_BIN_DIR:$PATH"

# Create skopeo mock executable
cat > "$MOCK_BIN_DIR/skopeo" << 'EOF'
#!/bin/bash
echo "🎯 Mock skopeo executable called with: $*" >&2

if [[ "$*" == *"inspect"* ]]; then
  image=""
  for arg in "$@"; do
    if [[ "$arg" == docker://* ]]; then
      image="$arg"
      break
    fi
  done
  
  echo "  → Inspecting image: $image" >&2
  
  ocp_version="4.15"  # default (no 'v' prefix - template adds it)
  if [[ "$image" == *"@sha256:comp1v414"* ]] || [[ "$image" == *"@sha256:comp2v414"* ]]; then
    ocp_version="4.14"
  elif [[ "$image" == *"@sha256:comp3v416"* ]] || [[ "$image" == *"@sha256:comp4v416"* ]]; then
    ocp_version="4.16"
  fi
  
  echo "  → Returning OCP version: $ocp_version" >&2
  
  cat <<JSONEOF
{
  "Name": "$image",
  "Labels": {
    "org.opencontainers.image.base.name": "registry.access.redhat.com/ubi9/ubi:$ocp_version"
  },
  "annotations": {
    "org.opencontainers.image.base.name": "registry.access.redhat.com/ubi9/ubi:$ocp_version"
  }
}
JSONEOF
  exit 0
fi

# For other commands, call real skopeo
exec /usr/bin/skopeo "$@"
EOF
chmod +x "$MOCK_BIN_DIR/skopeo"

echo "✅ Created mock executable: $MOCK_BIN_DIR/skopeo" >&2

# Create curl mock executable  
cat > "$MOCK_BIN_DIR/curl" << 'EOF'
#!/bin/bash
echo "🎯 Mock curl executable called" >&2

# Parse arguments
output_file=""
write_out=""
for ((i=1; i<=$#; i++)); do
  arg="${!i}"
  if [[ "$arg" == "-o" ]]; then
    ((i++))
    output_file="${!i}"
  elif [[ "$arg" == "-w" ]]; then
    ((i++))
    write_out="${!i}"
  fi
done

# Determine response based on URL pattern
json_response='{"data": []}'
http_status="200"

if [[ "$*" == *"docker_image_id%3D%3Dquay.io%2Fredhat-pending%2Fcatalog%3Av4.14%3Blast_update_date"* ]] && [[ "$*" != *"-published"* ]] && [[ "$*" != *"-all-published"* ]]; then
  echo "✅ Matched v4.14 catalog - returning comp1v414 as published" >&2
  json_response='{
    "data": [{
      "_id": "index-v4.14-multi",
      "docker_image_id": "quay.io/redhat-pending/catalog:v4.14",
      "related_images": [
        {"image": "quay.io/test/comp1@sha256:comp1v414", "digest": "sha256:comp1v414"}
      ]
    }]
  }'
elif [[ "$*" == *"docker_image_id%3D%3Dquay.io%2Fredhat-pending%2Fcatalog%3Av4.16%3Blast_update_date"* ]] && [[ "$*" != *"-published"* ]] && [[ "$*" != *"-all-published"* ]]; then
  echo "✅ Matched v4.16 catalog - returning comp3v416 as published" >&2
  json_response='{
    "data": [{
      "_id": "index-v4.16-multi",
      "docker_image_id": "quay.io/redhat-pending/catalog:v4.16",
      "related_images": [
        {"image": "quay.io/test/comp3@sha256:comp3v416", "digest": "sha256:comp3v416"}
      ]
    }]
  }'
else
  echo "⚠️  No pattern matched - returning empty data" >&2
fi

if [[ -n "$output_file" ]]; then
  echo "$json_response" > "$output_file"
else
  echo "$json_response"
fi

if [[ "$write_out" == "%{http_code}" ]]; then
  echo "$http_status"
fi

exit 0
EOF
chmod +x "$MOCK_BIN_DIR/curl"

echo "✅ Created mock executable: $MOCK_BIN_DIR/curl" >&2
echo "✅ PATH is now: $PATH" >&2
which skopeo >&2 || echo "❌ which skopeo failed" >&2
which curl >&2 || echo "❌ which curl failed" >&2

echo "==================================================================" >&2
echo "✅ MOCKS.SH LOADED - Mock functions exported: kubectl, skopeo, curl" >&2
echo "==================================================================" >&2
echo "Testing function accessibility:" >&2
type -t kubectl >&2 2>/dev/null || echo "❌ kubectl not accessible" >&2
type -t skopeo >&2 2>/dev/null || echo "❌ skopeo not accessible" >&2
type -t curl >&2 2>/dev/null || echo "❌ curl not accessible" >&2

# Test if functions will actually be called
echo "Testing which command will be executed:" >&2  
command -v skopeo >&2
command -V skopeo >&2 2>&1 || true

# Test if function works in subshell (critical for command substitution)
echo "Testing function in subshell:" >&2
test_result=$(type -t skopeo 2>&1) && echo "  Subshell sees skopeo as: $test_result" >&2 || echo "  ❌ Subshell cannot see skopeo" >&2

echo "==================================================================" >&2
