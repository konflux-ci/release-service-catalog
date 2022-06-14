# apply-mapping

Tekton task to apply a mapping to an Application Snapshot.

The purpose of this task is to merge a mapping with the components contained in an Application Snapshot.
The mapping is expected to be present in the passed `extraConfigPath`. If the file is not found or
the file contains no `mapping` key, the original Application Snapshot is returned. If there is a
`mapping` key, it is merged with the `components` key in the Application Snapshot based on component name.

A `mapped` result is also returned from this task containing a simple true/false value that is
meant to inform whether a mapped Application Snapshot is being returned or the original one.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| applicationSnapshot | The ApplicationSnapshot in JSON format to apply the mapping to | No | - |
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
      - name: applicationSnapshot
        value: '{"components":[{"name":"component1","containerImage":"quay.io/repo/component1:digest"}}]}'
      - name: extraConfigPath
        value: "path/to/file"
    workspaces:
      - name: config
        workspace: config_workspace
```
