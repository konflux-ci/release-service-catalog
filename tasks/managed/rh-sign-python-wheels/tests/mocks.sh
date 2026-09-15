#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function cosign() {
  echo Mock cosign called with: $*
  echo $* >> $(params.dataDir)/mock_cosign.txt

  if [[ "$1" == "attest-blob" ]]; then
    # Extract flags from arguments
    output_file=""
    bundle_file=""
    predicate_file=""
    has_rekor=false
    for arg in "$@"; do
      if [[ "${arg}" == --output-file=* ]]; then
        output_file="${arg#--output-file=}"
      elif [[ "${arg}" == --bundle=* ]]; then
        bundle_file="${arg#--bundle=}"
      elif [[ "${arg}" == --predicate=* ]]; then
        predicate_file="${arg#--predicate=}"
      elif [[ "${arg}" == --rekor-url=* ]]; then
        has_rekor=true
      fi
    done

    target_file="${bundle_file:-${output_file}}"

    if [[ -n "${target_file}" ]]; then
      # Build a statement from the predicate, matching real cosign behavior
      PREDICATE_CONTENT=$(cat "${predicate_file}" 2>/dev/null || echo '{}')
      STATEMENT=$(jq -n -c \
        --arg type "https://in-toto.io/Statement/v1" \
        --argjson predicate "${PREDICATE_CONTENT}" \
        '{_type: $type, predicate: $predicate}')
      ENCODED=$(echo -n "${STATEMENT}" | (base64 -w 0 2>/dev/null || base64 | tr -d '\n'))

      if [[ -n "${bundle_file}" ]]; then
        if [[ "${has_rekor}" == "true" ]]; then
          jq -n \
            --arg payload "${ENCODED}" \
            '{
              mediaType: "application/vnd.dev.sigstore.bundle.v0.3+json",
              verificationMaterial: {
                publicKey: {
                  hint: "up0mNQ14iTog8zfiFToRMQi/zwZAha+u5g1EbmNAVXY="
                },
                tlogEntries: [
                  {
                    logIndex: "12345",
                    logId: {
                      keyId: "wNI9atQGlz+VWfO6LRygH4QUfY/8W4RFwiT5i5WRgB0="
                    },
                    kindVersion: {
                      kind: "dsse",
                      version: "0.0.1"
                    },
                    integratedTime: "1789476777",
                    inclusionProof: {
                      logIndex: "12340",
                      rootHash: "Bx8krnSIP0NZnZtMzjPprpy0F/oV4I2p66Avmj5fn0U=",
                      treeSize: "12345",
                      hashes: ["OkYVKS0nERycZoEYOaUbs8mnYw3RPfT3YTlFP18k6pY="],
                      checkpoint: {
                        envelope: "rekor.sigstore.dev - 12345\n12345\nBx8krnSIP0NZnZtMzjPprpy0F/oV4I2p66Avmj5fn0U=\n"
                      }
                    }
                  }
                ]
              },
              dsseEnvelope: {
                payloadType: "application/vnd.in-toto+json",
                payload: $payload,
                signatures: [{keyid: "", sig: "MEUCIQC5mock5signature5here"}]
              }
            }' > "${bundle_file}"
        else
          jq -n \
            --arg payload "${ENCODED}" \
            '{
              mediaType: "application/vnd.dev.sigstore.bundle.v0.3+json",
              verificationMaterial: {
                publicKey: {
                  hint: "up0mNQ14iTog8zfiFToRMQi/zwZAha+u5g1EbmNAVXY="
                }
              },
              dsseEnvelope: {
                payloadType: "application/vnd.in-toto+json",
                payload: $payload,
                signatures: [{keyid: "", sig: "MEUCIQC5mock5signature5here"}]
              }
            }' > "${bundle_file}"
        fi
      else
        jq -n \
          --arg payload "${ENCODED}" \
          '{
            payloadType: "application/vnd.in-toto+json",
            payload: $payload,
            signatures: [{keyid: "", sig: "MEUCIQC5mock5signature5here"}]
          }' > "${output_file}"
      fi
    fi
    return 0
  fi

  return 0
}


