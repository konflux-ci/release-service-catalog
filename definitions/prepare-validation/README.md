# prepare-validation

Tekton task to extract a pull spec from an Application Snapshot.

The purpose of this task is to extract just a single component's pullSpec from a passed Application Snapshot.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| applicationSnapshot | The ApplicationSnapshot in JSON format to apply the mapping to | No | - |

## Example usage

This is an example usage of the `prepare-validation` task:

```
---
tasks:
  - name: prepare-validation
    taskRef:
      name: prepare-validation
    params:
      - name: applicationSnapshot
        value: '{"images":[{"component":"component1","pullSpec":"quay.io/repo/component1:digest"}}]}'
```
