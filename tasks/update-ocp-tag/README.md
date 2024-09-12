# update-ocp-tag
Tekton task to update pull-spec tag with the OCP version gotten from the get-ocp-version task. The replacement only
occurs when the {{ OCP_VERSION }} placeholder is present.

## Parameters

| Name       | Description                                                             | Optional | Default value |
|------------|-------------------------------------------------------------------------|----------|---------------|
| dataPath   | Path to the JSON string of the merged data to use in the data workspace | No       | -             |
| ocpVersion | OCP version fetched from fbcFragment                                    | No       | -             |

## Changes in 1.5.0
* Removed result updated-binaryImage from task

## Changes in 1.4.2
* Changed to skip validating the targetIndex when empty, as staged indexes does not have it set.

## Changes in 1.4.1
* Changed the replace_tag function to only replace the OCP version tag of an index image when the {{ OCP_VERSION }}
  placeholder is present
* Added the validateOcpVersion function to check if the index version matches with the version found in the base image

## Changes in 1.4.0
* Updated the base image used in this task

## Changes in 1.3.0
* Updated the base image used in this task

## Changes in 1.2.0
* Remove `dataPath` default value

## Changes in 1.0.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 0.2
* A new parameter exists called dataPath that specifies the path to the JSON string of merged data in the workspace
* fromIndex, targetIndex, and binaryImage are no longer task parameters
    * They are now pulled from the data json.

## Changes in 0.1
* update Tekton API to v1
