#!/usr/bin/env bash
set -eux

# Mock: oras — for `discover`, print a referrer digest derived from the image
# ref (the last positional arg) so each component discovers a distinct
# digest; for `pull`, drop a build-index.json into the -o output dir whose
# content is derived from that digest, so each component's build-index (and
# therefore its OSV output) is genuinely distinct.
oras() {
  # Debug logging must go to stderr: the real script captures `oras discover`
  # output via command substitution, and stdout noise here would corrupt it.
  echo "Mock oras called: $*" >&2
  local out="."
  local prev=""
  local last=""
  for a in "$@"; do
    if [ "$prev" = "-o" ]; then out="$a"; fi
    prev="$a"
    last="$a"
  done
  case "$1" in
    discover)
      # Derive a component name from the image ref, e.g.
      # registry.local/requests@sha256:bbb -> requests
      local name="${last%@*}"
      name="${name##*/}"
      echo "sha256:${name}-referrer"
      ;;
    pull)
      # $last is the digest reference produced by the `discover` case above.
      local name="${last#sha256:}"
      name="${name%-referrer}"
      mkdir -p "$out"
      cat > "$out/build-index.json" <<EOF
{"ecosystem":"pypi","version":{"upstream":"0.4.0","full":"0.4.0+rhlw.1","b":1,"n":0},
"primaryPurl":"pkg:pypi/${name}@0.4.0%2Brhlw.1","purls":["pkg:pypi/${name}@0.4.0%2Brhlw.1"],
"vulns":["CVE-2024-0001"]}
EOF
      ;;
    *) echo "Mock oras: unhandled subcommand $1" ;;
  esac
}
export -f oras

# Mock: slan-cuan generate-security-metadata — write an OSV file into
# --output-dir whose filename is derived from the build-index.json content it
# reads (via --workdir/--index-basedir/--index-filename), instead of a
# hardcoded constant, so distinct components produce distinct OSV filenames.
slan-cuan() {
  echo "Mock slan-cuan called: $*" >&2
  local outdir="" workdir="" basedir="" filename=""
  local prev=""
  for a in "$@"; do
    case "$prev" in
      --output-dir) outdir="$a" ;;
      --workdir) workdir="$a" ;;
      --index-basedir) basedir="$a" ;;
      --index-filename) filename="$a" ;;
    esac
    prev="$a"
  done
  local idxfile="${workdir}/${basedir}/${filename}"
  local name
  name=$(jq -r '.primaryPurl' "${idxfile}")
  name="${name#pkg:pypi/}"
  name="${name%%@*}"
  mkdir -p "$outdir"
  echo "{\"schema_version\":\"1.6.8\",\"id\":\"x_RHLW-CVE-2024-0001-${name}\"}" \
    > "$outdir/x_RHLW-CVE-2024-0001-${name}.json"
}
export -f slan-cuan
