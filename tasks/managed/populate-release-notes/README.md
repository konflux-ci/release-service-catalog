# populate-release-notes

Tekton task to populate fields of the releaseNotes  key in the data.json
file. It will update the data.json in place so that downstream tasks relying on
the releaseNotes data can use it. Additionally, it outputs a result with the
path to a file containing data used in component SBOM generation.

## Parameters

| Name         | Description                                                          | Optional | Default value |
|--------------|----------------------------------------------------------------------|----------|---------------|
| dataPath     | Path to the JSON string of the merged data to update                 | No       | -             |
| snapshotPath | Path to the JSON string of the mapped Snapshot in the data workspace | No       | -             |

## Changes in 3.0.3
* This task now overrides the releaseNotes.type field to `RHSA` if CVEs are provided

## Changes in 3.0.2
* Bump the utils image used in this task
  * The `get-image-architectures` script now uses `set -e` so that it fails
    if a `skopeo` or `oras` call fails

## Changes in 3.0.1
* If type is RHBA or RHEA, the task will ensure the `references` key exists (although it will be empty)

## Changes in 3.0.0
* Task renamed from `populate-release-notes-images` to `populate-release-notes`
* Task will now inject references if the `releaseNotes.type` is `RHSA`

## Changes in 2.3.1
* Fix shellcheck/checkton linting issues in the task and tests

## Changes in 2.3.0
* Export additional image data to a file for component SBOM generation

## Changes in 2.2.3
* Rename `components` in the CVE struct to `packages`

## Changes in 2.2.2
* Add component association information

## Changes in 2.2.1
* Add unique tag info to purl

## Changes in 2.2.0
* Updated to use the `rh-registry-repo` key from the snapshot JSON for constructing
  the image repository path, instead of relying on the data field. This change
  ensures that the task correctly references the internal Red Hat registry format.
* Removed the use of the `translate-delivery-repo` script as the task now directly
  accesses the `rh-registry-repo` value from the snapshot JSON.

## Changes in 2.1.0
* Updated the base image used in this task

## Changes in 2.0.0
* The `commonTags` parameter was removed in favor of the component tags in the snapshot spec file

## Changes in 1.4.0
* Updated the base image used in this task

## Changes in 1.3.0
* Updated the base image used in this task

## Changes in 1.2.1
* Fix the format and values of the images inside the resulting advisory data

## Changes in 1.2.0
* The task now looks for tags in each component of the snapshot spec file and uses them instead of the commonTags if
  any exist

## Changes in 1.1.0
* Existing CVE data is present in the resulting releaseNotes key instead of overwritten
* Update task image for fix in get-image-architectures script
  * util now outputs compact json

## Changes in 1.0.2
* Absorb change in refactored get-image-architectures script

## Changes in 1.0.1
* Update task image and make changes to accomodate for new `translate-delivery-repo` funtionality

## Changes in 1.0.0
* Task renamed from extract-release-notes-images to populate-release-notes-images

## Changes in 0.1.1
* Temp data file is stored in /tmp/ to work around permission issues in the container
