# prepare-skopeo-image-string

Tekton task to create a string from a snapshot that can be passed to skopeo.

The purpose of this task is to create a string that can be passed as an argument to skopeo inspect.
The task creates this string by extracting the containerImage value from the snapshot provided and
prepending 'docker://' to it.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| snapshot | The Snapshot in JSON format containing a single container image | No | - |

## Example usage

This is an example usage of the `prepare-skopeo-image-string` task:

```
---
tasks:
  - name: prepare-skopeo-image-string
    taskRef:
      name: prepare-skopeo-image-string
    params:
      - name: snapshot
        value: '{"components":[{"name":"component1","containerImage":"quay.io/repo/component1:digest"}]}'
```
