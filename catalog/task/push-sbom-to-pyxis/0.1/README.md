# push-sbom-to-pyxis

Tekton task that extracts sbom from a pull spec and pushes it to Pyxis.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| imageURLs | Space separated list of binary image URLs that are used to obtain SBOMs via cosign | No | - |
| containerImageIDs | Space separated list of Pyxis image IDs | No | - |
| pyxisSecret | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys: key and cert | No | - |
| server | The server type to use. Options are 'production' and 'stage' | Yes | production |
