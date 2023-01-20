# apply-mapping

Tekton task to apply a mapping to an Snapshot.

The purpose of this task is to merge a mapping with the components contained in an Snapshot.
The mapping is expected to be present in the passed `extraConfigPath`. If the file is not found or
the file contains no `mapping` key, the original Snapshot is returned. If there is a
`mapping` key, it is merged with the `components` key in the Snapshot based on component name.

A `mapped` result is also returned from this task containing a simple true/false value that is
meant to inform whether a mapped Snapshot is being returned or the original one.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| snapshot | The Snapshot in JSON format to apply the mapping to | No | - |
| extraConfigPath | The path to the config file containing the mapping | Yes | - |

## Example usage

This is an example usage of the `apply-mapping` task:

```
---
tasks:
  - name: apply-mapping
    taskRef:
      name: apply-mapping
    params:
      - name: snapshot
        value: '{"components":[{"name":"component1","containerImage":"quay.io/repo/component1:digest"}}]}'
      - name: extraConfigPath
        value: "path/to/file"
    workspaces:
      - name: config
        workspace: config_workspace
```
## Changes since 0.2

  * Base image was changed from `release-utils` to `release-base-image`

## Changes since 0.1 (milestone-8)

  * Task `apply-mapping` was changed
    * Task parameter `applicationSnapshot` value was changed
      * old: $(params.applicationSnapshot)
      * new: $(params.snapshot)
