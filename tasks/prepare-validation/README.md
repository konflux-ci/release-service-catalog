# prepare-validation

Tekton task to extract a pull spec from a Snapshot.

The purpose of this task is to extract just a single component's pullSpec from a passed Snapshot.

## Parameters

| Name     | Description                                         | Optional | Default value |
|----------|-----------------------------------------------------|----------|---------------|
| snapshot | The Snapshot in JSON format to apply the mapping to | No       | -             |

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

## Changes in 0.7.1
* Fix shellcheck/checkton linting issues in the task

## Changes in 0.7.0
* Updated the base image used in this task

## Changes in 0.6.0
* Updated the base image used in this task

## Changes in 0.4.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 0.3
* Update Tekton API to v1

## Changes in 0.2
* Base image was changed from `release-utils` to `release-base-image`
* The syntax for `taskRef.bundle` and `pipelineRef.bundle` is deprecated,
bundles resolver is used with new format.

## Changes in 0.1 (milestone-8)
* Task `prepare-validation` was changed
  * Task parameter `applicationSnapshot` value was changed
  * old: $(params.applicationSnapshot)
  * new: $(params.snapshot)
