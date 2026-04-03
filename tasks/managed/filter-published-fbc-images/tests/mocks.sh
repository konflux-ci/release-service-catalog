# mocks to be injected into task step scripts
echo "==================================================================" >&2
echo "🔧 MOCKS.SH BEING LOADED - START OF INJECTION" >&2
echo "==================================================================" >&2

# ---------------------------------------------------------------------------
# skopeo mock — returns OCP version from org.opencontainers.image.base.name
# Routes by image digest suffix to support multi-OCP tests.
# ---------------------------------------------------------------------------
skopeo() {
  echo "Mock skopeo called with: $*" >&2

  if [[ "$*" == *"inspect"* ]]; then
    local image=""
    for arg in "$@"; do
      if [[ "$arg" == docker://* ]]; then
        image="$arg"
        break
      fi
    done

    local ocp_version="4.15"  # default (no 'v' prefix — task adds it)
    if [[ "$image" == *"comp1v414"* ]] || [[ "$image" == *"comp2v414"* ]] || [[ "$image" == *"v414"* ]]; then
      ocp_version="4.14"
    elif [[ "$image" == *"comp3v416"* ]] || [[ "$image" == *"comp4v416"* ]] || [[ "$image" == *"v416"* ]]; then
      ocp_version="4.16"
    elif [[ "$image" == *"@sha256:invalidocp"* ]]; then
      ocp_version="4.14.1"  # invalid: three parts, triggers validation error
    fi

    cat <<EOF
{
  "annotations": {
    "org.opencontainers.image.base.name": "registry.access.redhat.com/ubi9/ubi:$ocp_version"
  }
}
EOF
    return 0
  fi

  command skopeo "$@"
}
export -f skopeo

# ---------------------------------------------------------------------------
# curl mock — should NOT be called after the Pyxis → Release CR migration.
# Fails loudly if invoked, so any regression to the Pyxis path is caught.
# ---------------------------------------------------------------------------
curl() {
  echo "ERROR: curl was called but should not be used by filter-published-fbc-images." >&2
  echo "  The task uses kubectl Release CR lookup, not Pyxis HTTP calls." >&2
  echo "  Arguments received: $*" >&2
  return 1
}
export -f curl

# ---------------------------------------------------------------------------
# kubectl mock — handles two calls made by filter-published-fbc-images:
#
#   1. get release <name> -n <ns> -o jsonpath=...
#      → returns application label (routes by release name)
#
#   2. get release -n <ns> -l appstudio.openshift.io/application=<app> -o json
#      → returns Release CR list JSON (routes by application label)
#
# Test scenarios are identified by the release name passed in releaseName param:
#
#   current-release-basic      app=test-app-basic   → prev release: abc123+ghi789 published
#   current-release-all        app=test-app-all     → prev release: all digests published
#   current-release-first      app=test-app-first   → no prior releases
#   current-release-multi      app=test-app-multi   → prior releases for v4.14 + v4.16
#   current-release-incomplete app=test-app-incomplete → prior release Released=False
#   current-release-rbac       app=test-app-rbac    → list fails (simulates RBAC denial)
#   current-release-malformed  app=test-app-malformed → list returns invalid JSON
#   current-release-partial    app=test-app-partial    → one of two fragments published
#   current-release-history    app=test-app-history    → two prior releases, same index (union)
#   current-release-multi-partial  app=test-app-multi-partial → multi-OCP + partial
#   current-release-no-artifacts   app=test-app-no-artifacts  → Released=True, no artifacts
#   current-release-no-app-label   (kubectl get <name> returns "", triggers safe fallback)
#   (any other name)           app=test-app-default    → no prior releases (safe default)
# ---------------------------------------------------------------------------
kubectl() {
  echo "Mock kubectl called with: $*" >&2

  if [[ "$1" == "get" && "$2" == "release" ]]; then
    # Detect single-resource get (name is 3rd positional, not a flag)
    if [[ "$3" != "-n" && "$3" != "-l" && "$3" != "-o" && -n "$3" ]]; then
      # Call 1: get release <name> -n <ns> -o jsonpath=...
      local release_name="$3"
      echo "  → Resolving application label for release: $release_name" >&2
      case "$release_name" in
        current-release-basic)      echo -n "test-app-basic" ;;
        current-release-all)        echo -n "test-app-all" ;;
        current-release-first)      echo -n "test-app-first" ;;
        current-release-multi)      echo -n "test-app-multi" ;;
        current-release-incomplete) echo -n "test-app-incomplete" ;;
        current-release-rbac)       echo -n "test-app-rbac" ;;
        current-release-malformed)  echo -n "test-app-malformed" ;;
        current-release-partial)        echo -n "test-app-partial" ;;
        current-release-history)        echo -n "test-app-history" ;;
        current-release-multi-partial)  echo -n "test-app-multi-partial" ;;
        current-release-no-artifacts)   echo -n "test-app-no-artifacts" ;;
        current-release-no-app-label)   echo -n "" ;;
        *)                              echo -n "test-app-default" ;;
      esac
      return 0
    else
      # Call 2: get release -n <ns> -l appstudio...=<app> -o json
      local app=""
      for arg in "$@"; do
        if [[ "$arg" =~ appstudio\.openshift\.io/application=(.+) ]]; then
          app="${BASH_REMATCH[1]}"
          break
        fi
      done
      echo "  → Listing releases for application: $app" >&2

      case "$app" in

        test-app-basic)
          # One prior completed release — abc123 and ghi789 published for v4.15
          cat <<'JSON'
{"items": [
  {
    "metadata": {"name": "prev-release-basic"},
    "status": {
      "conditions": [{"type": "Released", "status": "True"}],
      "artifacts": {"components": [
        {"fbc_fragment": "quay.io/test/comp1@sha256:abc123",
         "target_index": "quay.io/redhat-pending/catalog:v4.15"},
        {"fbc_fragment": "quay.io/test/comp3@sha256:ghi789",
         "target_index": "quay.io/redhat-pending/catalog:v4.15"}
      ]}
    }
  }
]}
JSON
          ;;

        test-app-all)
          # One prior completed release — all snapshot digests published
          cat <<'JSON'
{"items": [
  {
    "metadata": {"name": "prev-release-all"},
    "status": {
      "conditions": [{"type": "Released", "status": "True"}],
      "artifacts": {"components": [
        {"fbc_fragment": "quay.io/test/comp1@sha256:mno345",
         "target_index": "quay.io/redhat-pending/catalog:v4.16-all"},
        {"fbc_fragment": "quay.io/test/comp2@sha256:pqr678",
         "target_index": "quay.io/redhat-pending/catalog:v4.16-all"}
      ]}
    }
  }
]}
JSON
          ;;

        test-app-first)
          # No prior releases at all
          echo '{"items": []}'
          ;;

        test-app-multi)
          # Two prior releases — one for v4.14, one for v4.16, each with one fragment
          cat <<'JSON'
{"items": [
  {
    "metadata": {"name": "prev-release-v414"},
    "status": {
      "conditions": [{"type": "Released", "status": "True"}],
      "artifacts": {"components": [
        {"fbc_fragment": "quay.io/test/comp1@sha256:comp1v414",
         "target_index": "quay.io/redhat-pending/catalog:v4.14"}
      ]}
    }
  },
  {
    "metadata": {"name": "prev-release-v416"},
    "status": {
      "conditions": [{"type": "Released", "status": "True"}],
      "artifacts": {"components": [
        {"fbc_fragment": "quay.io/test/comp3@sha256:comp3v416",
         "target_index": "quay.io/redhat-pending/catalog:v4.16"}
      ]}
    }
  }
]}
JSON
          ;;

        test-app-incomplete)
          # Prior release exists but Released condition is False — must not count
          cat <<'JSON'
{"items": [
  {
    "metadata": {"name": "prev-release-incomplete"},
    "status": {
      "conditions": [{"type": "Released", "status": "False", "reason": "Failed"}],
      "artifacts": {"components": [
        {"fbc_fragment": "quay.io/test/comp1@sha256:abc123",
         "target_index": "quay.io/redhat-pending/catalog:v4.15"}
      ]}
    }
  }
]}
JSON
          ;;

        test-app-rbac)
          # Simulate RBAC denial — kubectl exits non-zero
          echo "Error from server (Forbidden): releases.appstudio.redhat.com is forbidden" >&2
          return 1
          ;;

        test-app-malformed)
          # Return syntactically invalid JSON
          echo '{"items": [{"broken": true, "status": {"conditions": [unclosed'
          ;;

        test-app-partial)
          # One of two fragments already published (comp1); comp2 is new
          cat <<'JSON'
{"items": [
  {
    "metadata": {"name": "prev-release-partial"},
    "status": {
      "conditions": [{"type": "Released", "status": "True"}],
      "artifacts": {"components": [
        {"fbc_fragment": "quay.io/test/comp1@sha256:frag111",
         "target_index": "quay.io/redhat-pending/catalog:v4.15"}
      ]}
    }
  }
]}
JSON
          ;;

        test-app-history)
          # Two prior releases for the SAME target index — tests union accumulation.
          # Release A: sha256:F1. Release B: sha256:F3. New snapshot has F1+F2+F3+F4.
          cat <<'JSON'
{"items": [
  {
    "metadata": {"name": "prev-release-A"},
    "status": {
      "conditions": [{"type": "Released", "status": "True"}],
      "artifacts": {"components": [
        {"fbc_fragment": "quay.io/test/comp1@sha256:F1",
         "target_index": "quay.io/redhat-pending/catalog:v4.15"}
      ]}
    }
  },
  {
    "metadata": {"name": "prev-release-B"},
    "status": {
      "conditions": [{"type": "Released", "status": "True"}],
      "artifacts": {"components": [
        {"fbc_fragment": "quay.io/test/comp3@sha256:F3",
         "target_index": "quay.io/redhat-pending/catalog:v4.15"}
      ]}
    }
  }
]}
JSON
          ;;

        test-app-multi-partial)
          # Multi-OCP + partial: v4.14 index has sha256:P1comp1v414 published; v4.16 nothing
          cat <<'JSON'
{"items": [
  {
    "metadata": {"name": "prev-v414-partial"},
    "status": {
      "conditions": [{"type": "Released", "status": "True"}],
      "artifacts": {"components": [
        {"fbc_fragment": "quay.io/test/comp1@sha256:P1comp1v414",
         "target_index": "quay.io/redhat-pending/catalog:v4.14"}
      ]}
    }
  }
]}
JSON
          ;;

        test-app-no-artifacts)
          # Prior Release is completed (Released=True) but has no artifacts field at all
          cat <<'JSON'
{"items": [
  {
    "metadata": {"name": "prev-no-artifacts"},
    "status": {
      "conditions": [{"type": "Released", "status": "True"}]
    }
  }
]}
JSON
          ;;

        *)
          # Safe default: no prior releases
          echo '{"items": []}'
          ;;
      esac
      return 0
    fi
  fi

  # Pass through any other kubectl calls (should not occur in normal test execution)
  command kubectl "$@"
}
export -f kubectl

# ---------------------------------------------------------------------------
# Create mock executables in PATH (required for command-substitution contexts)
# ---------------------------------------------------------------------------
MOCK_BIN_DIR="/tmp/filter-fbc-mocks-$$"
mkdir -p "$MOCK_BIN_DIR"
export PATH="$MOCK_BIN_DIR:$PATH"

# skopeo executable
cat > "$MOCK_BIN_DIR/skopeo" << 'SKOPEO_EOF'
#!/bin/bash
echo "🎯 Mock skopeo called with: $*" >&2
if [[ "$*" == *"inspect"* ]]; then
  image=""
  for arg in "$@"; do
    if [[ "$arg" == docker://* ]]; then image="$arg"; break; fi
  done
  ocp_version="4.15"
  if [[ "$image" == *"comp1v414"* ]] || [[ "$image" == *"comp2v414"* ]] || [[ "$image" == *"v414"* ]]; then
    ocp_version="4.14"
  elif [[ "$image" == *"comp3v416"* ]] || [[ "$image" == *"comp4v416"* ]] || [[ "$image" == *"v416"* ]]; then
    ocp_version="4.16"
  elif [[ "$image" == *"@sha256:invalidocp"* ]]; then
    ocp_version="4.14.1"
  fi
  cat <<EOF
{"annotations": {"org.opencontainers.image.base.name": "registry.access.redhat.com/ubi9/ubi:$ocp_version"}}
EOF
  exit 0
fi
exec /usr/bin/skopeo "$@"
SKOPEO_EOF
chmod +x "$MOCK_BIN_DIR/skopeo"

# curl executable — fails on any call
cat > "$MOCK_BIN_DIR/curl" << 'CURL_EOF'
#!/bin/bash
echo "ERROR: curl called — filter-published-fbc-images must not call curl (uses kubectl now)." >&2
echo "  Arguments: $*" >&2
exit 1
CURL_EOF
chmod +x "$MOCK_BIN_DIR/curl"

# kubectl executable — mirrors the bash function above
cat > "$MOCK_BIN_DIR/kubectl" << 'KUBECTL_EOF'
#!/bin/bash
echo "🎯 Mock kubectl called with: $*" >&2

if [[ "$1" == "get" && "$2" == "release" ]]; then
  if [[ "$3" != "-n" && "$3" != "-l" && "$3" != "-o" && -n "$3" ]]; then
    release_name="$3"
    echo "  → Resolving application label for: $release_name" >&2
    case "$release_name" in
      current-release-basic)          printf "test-app-basic" ;;
      current-release-all)            printf "test-app-all" ;;
      current-release-first)          printf "test-app-first" ;;
      current-release-multi)          printf "test-app-multi" ;;
      current-release-incomplete)     printf "test-app-incomplete" ;;
      current-release-rbac)           printf "test-app-rbac" ;;
      current-release-malformed)      printf "test-app-malformed" ;;
      current-release-partial)        printf "test-app-partial" ;;
      current-release-history)        printf "test-app-history" ;;
      current-release-multi-partial)  printf "test-app-multi-partial" ;;
      current-release-no-artifacts)   printf "test-app-no-artifacts" ;;
      current-release-no-app-label)   printf "" ;;
      *)                              printf "test-app-default" ;;
    esac
    exit 0
  else
    app=""
    for arg in "$@"; do
      if [[ "$arg" =~ appstudio\.openshift\.io/application=(.+) ]]; then
        app="${BASH_REMATCH[1]}"
        break
      fi
    done
    echo "  → Listing releases for app: $app" >&2

    case "$app" in
      test-app-basic)
        cat <<'JSON'
{"items": [{"metadata": {"name": "prev-release-basic"}, "status": {"conditions": [{"type": "Released", "status": "True"}], "artifacts": {"components": [{"fbc_fragment": "quay.io/test/comp1@sha256:abc123", "target_index": "quay.io/redhat-pending/catalog:v4.15"}, {"fbc_fragment": "quay.io/test/comp3@sha256:ghi789", "target_index": "quay.io/redhat-pending/catalog:v4.15"}]}}}]}
JSON
        ;;
      test-app-all)
        cat <<'JSON'
{"items": [{"metadata": {"name": "prev-release-all"}, "status": {"conditions": [{"type": "Released", "status": "True"}], "artifacts": {"components": [{"fbc_fragment": "quay.io/test/comp1@sha256:mno345", "target_index": "quay.io/redhat-pending/catalog:v4.16-all"}, {"fbc_fragment": "quay.io/test/comp2@sha256:pqr678", "target_index": "quay.io/redhat-pending/catalog:v4.16-all"}]}}}]}
JSON
        ;;
      test-app-first)
        echo '{"items": []}'
        ;;
      test-app-multi)
        cat <<'JSON'
{"items": [{"metadata": {"name": "prev-v414"}, "status": {"conditions": [{"type": "Released", "status": "True"}], "artifacts": {"components": [{"fbc_fragment": "quay.io/test/comp1@sha256:comp1v414", "target_index": "quay.io/redhat-pending/catalog:v4.14"}]}}}, {"metadata": {"name": "prev-v416"}, "status": {"conditions": [{"type": "Released", "status": "True"}], "artifacts": {"components": [{"fbc_fragment": "quay.io/test/comp3@sha256:comp3v416", "target_index": "quay.io/redhat-pending/catalog:v4.16"}]}}}]}
JSON
        ;;
      test-app-incomplete)
        cat <<'JSON'
{"items": [{"metadata": {"name": "prev-incomplete"}, "status": {"conditions": [{"type": "Released", "status": "False", "reason": "Failed"}], "artifacts": {"components": [{"fbc_fragment": "quay.io/test/comp1@sha256:abc123", "target_index": "quay.io/redhat-pending/catalog:v4.15"}]}}}]}
JSON
        ;;
      test-app-rbac)
        echo "Error from server (Forbidden): releases.appstudio.redhat.com is forbidden" >&2
        exit 1
        ;;
      test-app-malformed)
        echo '{"items": [{"broken": true, "status": {"conditions": [unclosed'
        ;;
      test-app-partial)
        cat <<'JSON'
{"items": [{"metadata": {"name": "prev-partial"}, "status": {"conditions": [{"type": "Released", "status": "True"}], "artifacts": {"components": [{"fbc_fragment": "quay.io/test/comp1@sha256:frag111", "target_index": "quay.io/redhat-pending/catalog:v4.15"}]}}}]}
JSON
        ;;
      test-app-history)
        cat <<'JSON'
{"items": [{"metadata": {"name": "prev-A"}, "status": {"conditions": [{"type": "Released", "status": "True"}], "artifacts": {"components": [{"fbc_fragment": "quay.io/test/comp1@sha256:F1", "target_index": "quay.io/redhat-pending/catalog:v4.15"}]}}}, {"metadata": {"name": "prev-B"}, "status": {"conditions": [{"type": "Released", "status": "True"}], "artifacts": {"components": [{"fbc_fragment": "quay.io/test/comp3@sha256:F3", "target_index": "quay.io/redhat-pending/catalog:v4.15"}]}}}]}
JSON
        ;;
      test-app-multi-partial)
        cat <<'JSON'
{"items": [{"metadata": {"name": "prev-v414-partial"}, "status": {"conditions": [{"type": "Released", "status": "True"}], "artifacts": {"components": [{"fbc_fragment": "quay.io/test/comp1@sha256:P1comp1v414", "target_index": "quay.io/redhat-pending/catalog:v4.14"}]}}}]}
JSON
        ;;
      test-app-no-artifacts)
        cat <<'JSON'
{"items": [{"metadata": {"name": "prev-no-artifacts"}, "status": {"conditions": [{"type": "Released", "status": "True"}]}}]}
JSON
        ;;
      *)
        echo '{"items": []}'
        ;;
    esac
    exit 0
  fi
fi

command kubectl "$@"
KUBECTL_EOF
chmod +x "$MOCK_BIN_DIR/kubectl"

echo "✅ Created mock executables in: $MOCK_BIN_DIR" >&2
echo "✅ PATH: $PATH" >&2

echo "==================================================================" >&2
echo "✅ MOCKS.SH LOADED — kubectl, skopeo, curl stubs active" >&2
echo "==================================================================" >&2
