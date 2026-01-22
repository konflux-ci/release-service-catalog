#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function cosign() {
  echo Mock cosign called with: $*
  echo $* >> $(params.dataDir)/mock_cosign.txt

  if [[ "$1" == "attest-blob" ]]; then
    # Extract the output file from arguments
    output_file=""
    for arg in "$@"; do
      if [[ "$arg" == --output-file=* ]]; then
        output_file="${arg#--output-file=}"
      fi
    done

    if [[ -n "$output_file" ]]; then
      # Create a mock DSSE envelope
      cat > "$output_file" << 'DSSE_EOF'
{
  "payloadType": "application/vnd.in-toto+json",
  "payload": "eyJfdHlwZSI6Imh0dHBzOi8vaW4tdG90by5pby9TdGF0ZW1lbnQvdjAuMSJ9",
  "signatures": [
    {
      "keyid": "",
      "sig": "MEUCIQC5mock5signature5here"
    }
  ]
}
DSSE_EOF
    fi
    return 0
  fi

  return 0
}


