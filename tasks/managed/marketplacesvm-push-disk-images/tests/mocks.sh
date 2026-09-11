#!/usr/bin/env bash
set -euxo pipefail

# mocks to be injected into task step scripts

# extract_disk_image_files calls select-oci-auth and skopeo as subprocesses,
# which do not see bash functions. Put binaries on PATH for that fallback.
_MOCK_BIN="$(mktemp -d -p /var/workdir)"
cat > "${_MOCK_BIN}/select-oci-auth" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '{}'
EOF
chmod +x "${_MOCK_BIN}/select-oci-auth"

cat > "${_MOCK_BIN}/skopeo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'Mock skopeo called with: %s\n' "$*" >&2
printf '%s\n' "$*" >> "$(params.dataDir)/mock_skopeo.txt"

out_dir=""
for arg in "$@"; do
    if [[ "${arg}" == dir:* ]]; then
        out_dir="${arg#dir:}"
    fi
done
if [[ -z "${out_dir}" ]]; then
    echo "Error: Unexpected call to skopeo" >&2
    exit 1
fi
mkdir -p "${out_dir}"

if [[ "$*" == *"layered-skopeo-fail"* ]]; then
    echo "Simulating failed skopeo copy" >&2
    exit 1
fi

write_manifest() {
    local layers_json="${1}"
    jq -n --argjson layers "${layers_json}" '{
      schemaVersion: 2,
      mediaType: "application/vnd.oci.image.manifest.v1+json",
      config: {
        mediaType: "application/vnd.oci.image.config.v1+json",
        digest: "sha256:config",
        size: 2
      },
      layers: $layers
    }' > "${out_dir}/manifest.json"
}

if [[ "$*" == *"layered-whiteout"* ]]; then
    mkdir -p "${out_dir}/l1/releases" "${out_dir}/l2/releases"
    echo "dummy disk image content" > "${out_dir}/l1/releases/test-disk-image.raw"
    : > "${out_dir}/l2/releases/.wh.test-disk-image.raw"
    tar -C "${out_dir}/l1" -cf "${out_dir}/layer1" releases
    tar -C "${out_dir}/l2" -cf "${out_dir}/layer2" releases
    rm -rf "${out_dir}/l1" "${out_dir}/l2"
    write_manifest "$(jq -n '[
      {"mediaType":"application/vnd.oci.image.layer.v1.tar","digest":"sha256:layer1","size":1},
      {"mediaType":"application/vnd.oci.image.layer.v1.tar","digest":"sha256:layer2","size":1}
    ]')"
    exit 0
fi

if [[ "$*" == *"layered-missing"* ]]; then
    tar -cf "${out_dir}/layerblob" -T /dev/null
    write_manifest "$(jq -n '[
      {"mediaType":"application/vnd.oci.image.layer.v1.tar","digest":"sha256:layerblob","size":1}
    ]')"
    exit 0
fi

mkdir -p "${out_dir}/work/releases"
echo "dummy disk image content" > "${out_dir}/work/releases/test-disk-image.raw"
tar -C "${out_dir}/work" -cf "${out_dir}/layerblob" releases
rm -rf "${out_dir}/work"
write_manifest "$(jq -n '[
  {"mediaType":"application/vnd.oci.image.layer.v1.tar","digest":"sha256:layerblob","size":1}
]')"
EOF
chmod +x "${_MOCK_BIN}/skopeo"
export PATH="${_MOCK_BIN}:${PATH}"

function select-oci-auth() {
    echo "Mock select-oci-auth called with: $*"
    echo "$*" >> "$(params.dataDir)/mock_select-oci-auth.txt"

    if [[ "$*" == *"fail-raw-disk-image@sha256:123456" ]]; then
        echo "Simulating failed select-oci-auth"
        exit 1
    fi
}

function oras() {
    echo "Mock oras called with: $*"
    echo "$*" >> "$(params.dataDir)/mock_oras.txt"
    pwd >> "$(params.dataDir)/mock_oras_workdir.txt"

    if [[ "$*" != "pull --registry-config"* ]]; then
        echo "Error: Unexpected call to oras"
        return 1
    fi

    if [[ "$*" == *"layered-oras-fail"* ]]; then
        echo "Simulating failed oras pull"
        return 1
    fi

    # Missing mapped files: successful pull that leaves the source absent.
    if [[ "$*" == *"layered-missing"* ]] || \
        [[ "$*" == *"layered-whiteout"* ]] || \
        [[ "$*" == *"layered-skopeo-fail"* ]]; then
        return 0
    fi

    if [[ "$*" == *"layered-"* ]]; then
        mkdir -p releases
        echo "dummy disk image content" > releases/test-disk-image.raw
        return 0
    fi

    # Simulate downloaded artifact: create a compressed disk image
    # Determine the disk format from the pullspec
    if [[ "$*" == *"azure"* ]]; then
        echo "dummy disk image content" | gzip > disk.vhd.gz
    else
        echo "dummy disk image content" | gzip > disk.raw.gz
    fi
}

function pushsource-ls() {
    # Capture the staged directory contents before running pushsource-ls
    for arg in "$@"; do
        if [[ "${arg}" == staged:* ]]; then
            local staged_dir="${arg#staged:}"
            find "${staged_dir}" -type f -o -type d | sort > "$(params.dataDir)/mock_staged_dir.txt"
            break
        fi
    done
    command pushsource-ls "$@" 2>&1 | tee "$(params.dataDir)/mock_pushsource_ls.txt"
    return "${PIPESTATUS[0]}"
}

function marketplacesvm_push_wrapper() {
    echo "Mock marketplacesvm_push_wrapper called with: $*"
    echo "$*" > "$(params.dataDir)/mock_wrapper.txt"
    echo "${CLOUD_CREDENTIALS}" > "$(params.dataDir)/mock_cloud_credentials.txt"

    /home/pubtools-marketplacesvm-wrapper/marketplacesvm_push_wrapper "$@" --dry-run

    if ! [[ "${?}" -eq 0 ]]; then
        echo "Unexpected call to marketplacesvm_push_wrapper"
        exit 1
    fi

    # create fake artifacts which would be created by pubtools-marketplacesvm-marketplace-push
    mkdir -p artifacts/20260430181240/
    touch artifacts/20260430181240/pushitems.jsonl
    touch artifacts/20260430181240/clouds.json
}
