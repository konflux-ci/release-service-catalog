# push-sbom-to-pyxis

Tekton task that extracts sboms from pull specs and pushes them to Pyxis.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| mappedSnapshot | The mapped snapshot in JSON format | No | - |
| containerImageIDs | Space separated list of Pyxis image IDs | No | - |
| pyxisSecret | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys: key and cert | No | - |
| server | The server type to use. Options are 'production' and 'stage' | Yes | production |
