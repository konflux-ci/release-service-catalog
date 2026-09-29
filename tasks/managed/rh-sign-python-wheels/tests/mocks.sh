#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function cosign() {
  echo Mock cosign called with: $*
  echo $* >> $(params.dataDir)/mock_cosign.txt

  if [[ "$1" == "attest-blob" ]]; then
    # Extract the output file from arguments
    output_file=""
    predicate_file=""
    for arg in "$@"; do
      if [[ "$arg" == --output-file=* ]]; then
        output_file="${arg#--output-file=}"
      elif [[ "$arg" == --predicate=* ]]; then
        predicate_file="${arg#--predicate=}"
      fi
    done

    if [[ -n "$output_file" ]]; then
      # Build a statement from the predicate, matching real cosign behavior
      PREDICATE_CONTENT=$(cat "$predicate_file" 2>/dev/null || echo '{}')
      STATEMENT=$(jq -n -c \
        --arg type "https://in-toto.io/Statement/v1" \
        --argjson predicate "$PREDICATE_CONTENT" \
        '{_type: $type, predicate: $predicate}')
      ENCODED=$(echo -n "$STATEMENT" | base64 -w 0)

      jq -n \
        --arg payload "$ENCODED" \
        '{
          payloadType: "application/vnd.in-toto+json",
          payload: $payload,
          signatures: [{keyid: "", sig: "MEUCIQC5mock5signature5here"}]
        }' > "$output_file"
    fi
    return 0
  fi

  return 0
}


