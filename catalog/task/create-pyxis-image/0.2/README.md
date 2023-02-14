# create-pyxis-image

Tekton task that pushes metadata to Pyxis for all container images contained in a snapshot that is the
result of the `apply-mapping` task. It first extracts the containerImages from the snapshot, then runs
`skopeo inspect` on each, before finally pushing metadata to Pyxis.

The IDs of the created `containerImage` Pyxis objects are stored as a task result with each ID separated
by a new line.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| server | The server type to use. Options are 'production' and 'stage' | Yes | production |
| pyxisSecret | The kubernetes secret to use to authenticate to Pyxis | No | - |
| certified | If set to true, the images will be marked as certified in their Pyxis entries | Yes | false |
| tag | The tag to use when pushing the container image metadata to Pyxis | No | - |
| isLatest | If set to true, the images will have a latest tag added with their Pyxis entries | Yes | false |
| mappedSnapshot | The mapped snapshot in JSON format | No | - |

## Changes since 0.1

* Fix for incorrect snapshot param.
