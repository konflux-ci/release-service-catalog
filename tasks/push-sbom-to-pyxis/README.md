# push-sbom-to-pyxis

Tekton task that extracts sboms from pull specs and pushes them to Pyxis.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| snapshotPath | Path to the JSON string of the mapped Snapshot spec in the data workspace | Yes | mapped_snapshot.json |
| containerImageIDs | Space separated list of Pyxis image IDs | No | - |
| pyxisSecret | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys: key and cert | No | - |
| server | The server type to use. Options are 'production' and 'stage' | Yes | production |

## Changes since 0.3.0
* Update image reference
  - The new image includes performance optimizations which should increase the performance of pushing sbom
    components to Pyxis by over 50 %

## Changes since 0.2
* Update Tekton API to v1

## Changes since 0.1
* mappedSnapshot parameter was removed and snapshotPath parameter was added
  * Instead of passing a json string representing the snapshot, the snapshot spec should exist in the data workspace
    in the filename provided by snapshotPath.
