function create_product_sbom() {
  echo Mock create_product_sbom called with: "$*"
  echo "$*" >> "$(params.dataDir)/mock_create.txt"

  if [[ "$1" != "--data-path" ]] ||
     [[ "$2" != "$(params.dataDir)/data.json" ]] ||
     [[ "$3" != "--snapshot-path" ]] ||
     [[ "$4" != "$(params.dataDir)/snapshot_spec.json" ]] ||
     [[ "$5" != "--release-id" ]] ||
     [[ "$6" != "$(params.releaseId)" ]] ||
     [[ "$7" != "--output-path" ]] ||
     [[ "$8" != "$(params.dataDir)/sboms" ]]; then
    echo "Error: Unexpected call"
    exit 1
  fi
}
