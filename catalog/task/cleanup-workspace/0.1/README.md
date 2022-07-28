# cleanup-workspace

Tekton task to delete a given directory in a passed workspace.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| subdirectory | The directory to remove within the workspace | No | - |

## Example usage

This is an example usage of the `cleanup-workpace` task:

```
---
tasks:
  - name: cleanup-workspace
    taskRef:
      name: cleanup-workspace
    params:
      - name: subdirectory
        value: "some/directory"
    workspaces:
      - name: input
        workspace: input_workspace
```
