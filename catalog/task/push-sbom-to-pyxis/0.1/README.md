# push-sbom-to-pyxis

Tekton task that extracts sbom from a pull spec and pushes it to Pyxis.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| imageURL | Image URL | No | - |

## Example usage

This is an example usage of the `push-sbom-to-pyxis` task:

```
---
tasks:
  - name: push-sbom-to-pyxis
    taskRef:
      name: push-sbom-to-pyxis
    params:
      - name: imageURL
        value: 'quay.io/my-org/my-repo:latest'
```
