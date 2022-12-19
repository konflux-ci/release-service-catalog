# skopeo-inspect

Tekton task that executes `skopeo inspect` on an image and saves the result.

The output is saved to the `skopeo-inspect.json` file in the mounted workspace.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| imageURL | Image URL | No | - |

## Example usage

This is an example usage of the `skopeo-inspect` task:

```
---
tasks:
  - name: skopeo-inspect
    taskRef:
      name: skopeo-inspect
    params:
      - name: imageURL
        value: 'docker://quay.io/hacbs-release/release-utils:latest'
    workspaces:
      - name: output
        workspace: output_workspace
```
