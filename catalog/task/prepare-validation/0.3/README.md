# prepare-validation

Tekton task to extract a pull spec from a Snapshot.

The purpose of this task is to extract just a single component's pullSpec from a passed Snapshot.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| snapshot | The Snapshot in JSON format to apply the mapping to | No | - |

## Example usage

This is an example usage of the `prepare-validation` task:

```
---
tasks:
  - name: prepare-validation
    taskRef:
      name: prepare-validation
    params:
      - name: snapshot
        value: '{"components":[{"name":"component1","containerImage":"quay.io/repo/component1:digest"}}]}'
```
## Changes since 0.2

  * Base image was changed from `release-utils` to `release-base-image`

## Changes since 0.1 (milestone-8)

  * Task `prepare-validation` was changed
    * Task parameter `applicationSnapshot` value was changed
      * old: $(params.applicationSnapshot)
      * new: $(params.snapshot)
