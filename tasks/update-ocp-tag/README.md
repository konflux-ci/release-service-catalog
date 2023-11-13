# update-ocp-tag

Tekton task to update version tag of FBC pull-spec
 `fromIndex`, `targetIndex` and `binaryImage` with the 
 provided OCP version.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| dataPath | Path to the JSON string of the merged data to use in the data workspace | Yes | data.json |
| ocpVersion |  OCP version fetched from fbcFragment | No | - |

## Changes since 1.0.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes since 0.2
* A new parameter exists called dataPath that specifies the path to the JSON string of merged data in the workspace
* fromIndex, targetIndex, and binaryImage are no longer task parameters
    * They are now pulled from the data json.

## Changes since 0.1
- update Tekton API to v1