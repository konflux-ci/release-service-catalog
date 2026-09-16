#!/usr/bin/env bash
set -eux

# Mock: oras — for `discover`, print a referrer digest; for `pull`, drop a
# canned build-index.json into the current -o output dir.
oras() {
  echo "Mock oras called: $*"
  local out="."
  local prev=""
  for a in "$@"; do
    if [ "$prev" = "-o" ]; then out="$a"; fi
    prev="$a"
  done
  case "$1" in
    discover) echo "sha256:deadbeef" ;;
    pull)
      mkdir -p "$out"
      cat > "$out/build-index.json" <<'EOF'
{"ecosystem":"pypi","version":{"upstream":"0.4.0","full":"0.4.0+rhlw.1","b":1,"n":0},
"primaryPurl":"pkg:pypi/ntplib@0.4.0%2Brhlw.1","purls":["pkg:pypi/ntplib@0.4.0%2Brhlw.1"],
"vulns":["CVE-2024-0001"]}
EOF
      ;;
    *) echo "Mock oras: unhandled subcommand $1" ;;
  esac
}
export -f oras

# Mock: slan-cuan generate-security-metadata — write a canned OSV file into
# the --output-dir and return success, instead of calling OSIDB.
slan-cuan() {
  echo "Mock slan-cuan called: $*"
  local outdir=""
  local prev=""
  for a in "$@"; do
    if [ "$prev" = "--output-dir" ]; then outdir="$a"; fi
    prev="$a"
  done
  mkdir -p "$outdir"
  echo '{"schema_version":"1.6.8","id":"x_RHLW-CVE-2024-0001-0.4.0"}' \
    > "$outdir/x_RHLW-CVE-2024-0001-0.4.0.json"
}
export -f slan-cuan
