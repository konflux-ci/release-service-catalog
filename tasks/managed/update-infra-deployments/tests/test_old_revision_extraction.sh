#!/usr/bin/env bash
#
# Tests for the OLD_REVISION extraction logic in the run-update-script step.
# Run locally: bash test_old_revision_extraction.sh
#

set -uo pipefail

PASSED=0
FAILED=0

check() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $name"
        ((PASSED++))
    else
        echo "  FAIL: $name (expected='$expected' got='$actual')"
        ((FAILED++))
    fi
}

extract_old_revision() {
    echo "$1" | grep -E '^-\s+(newTag|digest):' | head -1 | awk '{print $NF}' || true
}

echo "============================================================"
echo "  OLD_REVISION extraction — newTag field"
echo "============================================================"
DIFF=" some context
-    newTag: abc123def456
+    newTag: 999888777666
 more context"
echo "  Input:    -    newTag: abc123def456"
RESULT=$(extract_old_revision "$DIFF")
echo "  Result:   '$RESULT'"
check "extracts old newTag value" "abc123def456" "$RESULT"

echo ""
echo "============================================================"
echo "  OLD_REVISION extraction — digest field (sha256)"
echo "============================================================"
DIGEST="sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
DIFF=" some context
-    digest: ${DIGEST}
+    digest: sha256:9999999999999999999999999999999999999999999999999999999999999999
 more context"
echo "  Input:    -    digest: ${DIGEST:0:40}..."
RESULT=$(extract_old_revision "$DIFF")
echo "  Result:   '$RESULT'"
check "extracts old digest value" "$DIGEST" "$RESULT"

echo ""
echo "============================================================"
echo "  OLD_REVISION extraction — Helm version field (should NOT match)"
echo "============================================================"
DIFF=" some context
-    version: 1.2.3
+    version: 1.3.0
 more context"
echo "  Input:    -    version: 1.2.3"
RESULT=$(extract_old_revision "$DIFF")
echo "  Result:   '$RESULT'"
check "returns empty (version field ignored)" "" "$RESULT"

echo ""
echo "============================================================"
echo "  OLD_REVISION extraction — no diff (empty input)"
echo "============================================================"
echo "  Input:    (empty)"
RESULT=$(extract_old_revision "")
echo "  Result:   '$RESULT'"
check "returns empty" "" "$RESULT"

echo ""
echo "============================================================"
echo "  OLD_REVISION extraction — multiple fields (takes first)"
echo "============================================================"
DIFF="-    newTag: first_sha
+    newTag: new_sha_1
-    newTag: second_sha
+    newTag: new_sha_2"
echo "  Input:    two newTag changes (first_sha, second_sha)"
RESULT=$(extract_old_revision "$DIFF")
echo "  Result:   '$RESULT'"
check "extracts first match only" "first_sha" "$RESULT"

echo ""
echo "============================================================"
echo "  OLD_REVISION extraction — mixed digest and newTag (takes first)"
echo "============================================================"
DIFF="-    digest: sha256:olddigest
+    digest: sha256:newdigest
-    newTag: oldtag
+    newTag: newtag"
echo "  Input:    digest then newTag"
RESULT=$(extract_old_revision "$DIFF")
echo "  Result:   '$RESULT'"
check "extracts first match (digest)" "sha256:olddigest" "$RESULT"

echo ""
echo "============================================================"
echo "  containerImage extraction from snapshot.json"
echo "============================================================"
echo "  (same snapshot format used by 12+ tasks/tests in the repo)"
TMPDIR=$(mktemp -d)
cat > "${TMPDIR}/snapshot.json" << 'EOF'
{
  "application": "myapp",
  "components": [
    {
      "name": "comp",
      "containerImage": "quay.io/konflux-ci/kyverno/kyverno@sha256:abc123",
      "source": {
        "git": {
          "revision": "50ea70d3999647e328e19ab1700ed78775017f55",
          "url": "https://github.com/konflux-ci/kyverno"
        }
      }
    }
  ]
}
EOF
echo "  Input:    snapshot with containerImage='quay.io/konflux-ci/kyverno/kyverno@sha256:abc123'"
RESULT=$(jq -r .components[0].containerImage "${TMPDIR}/snapshot.json")
echo "  Result:   '$RESULT'"
check "extracts containerImage" "quay.io/konflux-ci/kyverno/kyverno@sha256:abc123" "$RESULT"

echo ""
echo "============================================================"
echo "  originRepo extraction from snapshot.json"
echo "============================================================"
RESULT=$(jq -r .components[0].source.git.url "${TMPDIR}/snapshot.json")
echo "  Input:    same snapshot"
echo "  Result:   '$RESULT'"
check "extracts originRepo" "https://github.com/konflux-ci/kyverno" "$RESULT"

echo ""
echo "============================================================"
echo "  revision extraction from snapshot.json"
echo "============================================================"
RESULT=$(jq -r .components[0].source.git.revision "${TMPDIR}/snapshot.json")
echo "  Input:    same snapshot"
echo "  Result:   '$RESULT'"
check "extracts revision" "50ea70d3999647e328e19ab1700ed78775017f55" "$RESULT"

rm -rf "${TMPDIR}"

echo ""
echo "============================================================"
TOTAL=$((PASSED + FAILED))
echo "  RESULTS: ${PASSED}/${TOTAL} passed, ${FAILED} failed"
echo "============================================================"

[ "$FAILED" -eq 0 ] || exit 1
