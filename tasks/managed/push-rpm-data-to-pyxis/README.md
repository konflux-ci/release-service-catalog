# push-rpm-data-to-pyxis

Tekton task that extracts all rpms from the sboms and pushes them to Pyxis as an RPM Manifest.
In addition, it will also update ContainerImage.content_sets field in Pyxis to include
all repository_id strings found in rpm purl strings in the sboms.

## Parameters

| Name                    | Description                                                                                                                | Optional  | Default value           |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|-----------|-------------------------|
| pyxisJsonPath           | Path to the JSON string of the saved Pyxis data in the data workspace                                                      | No        | -                       |
| pyxisSecret             | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys: key and cert                          | No        | -                       |
| server                  | The server type to use. Options are 'production','production-internal,'stage-internal' and 'stage'.                        | No        | ""                      |
| concurrentLimit         | The maximum number of images to be processed at once                                                                       | Yes       | 4                       |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes       | empty                   |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes       | 1d                      |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes       | ""                      |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes       | ""                      | 
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes       | ""                      |
| subdirectory            | Subdirectory inside the workspace to be used                                                                               | Yes       | ""                      |
| dataDir                 | The location where data will be stored                                                                                     | Yes       | $(workspaces.data.path) |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No        | ""                      |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No        | ""                      |

## Changes in 3.0.0
* Remove the `sbomPath` result.

## Changes in 2.0.0
* This task now supports Trusted artifacts

## Changes in 1.4.0
* Updated the base image used in this task
  * The new image supports extracting rpm summaries from sbom annotations

## Changes in 1.3.4
* Updated the base image used in this task
  * The new image avoids failing on purls that miss qualifiers. Instead, such entries are skipped

## Changes in 1.3.3
* Fix shellcheck/checkton linting issues in the task and tests

## Changes in 1.3.2
* Updated the base image used in this task
  * The new image avoids failing on invalid purl strings

## Changes in 1.3.1
* Avoid "dir already exists" error in case the task is retried in a pipelinerun

## Changes in 1.3.0
* Updated the base image used in this task
  * The new image ignores the `gpg-pubkey` rpm package

## Changes in 1.2.0
* Change SBOM download location to a subdir of the data workspace, so that other tasks can
  access the downloaded SBOMs. A new result `sbomPath` is added to store the path the SBOMs
  are downloaded to.

## Changes in 1.1.0
* Added support for SPDX sbom format
  * If sbom format is SPDX, call `upload_rpm_data`, if it's CycloneDX, call
    `upload_rpm_data_cyclonedx`
  * The image is updated to include the new functionality

## Changes in 1.0.3
* Updated the step image used in this task
  * Added handling for sbom entries that do not explicitly specify the publisher.

## Changes in 1.0.2
* Updated the base image used in this task
  * A typo in `upload_rpm_data.py` was fixed and now we should correctly save
    the gpg field in Pyxis

## Changes in 1.0.1
* Updated the base image used in this task

## Changes in 1.0.0
* Renamed task from `push-rpm-manifest-to-pyxis` to `push-rpm-data-to-pyxis`
* Updated the image used in this task
  * The `upload_rpm_manifest` is renamed to `upload_rpm_data` and on top of RPM Manifest,
    it also updates the ContainerImage.content_sets field in Pyxis

## Changes in 0.4.4
* Updated the base image used in this task
  * The new image contains an updated upload_rpm_manifest script that will retry the POST
    request if it fails with error code 504

## Changes in 0.4.3
* Create new docker config for each `cosign download sbom` call
  * It only contains an entry for the specific image
  * This is to fix a bug with partial oci auth matches

## Changes in 0.4.2
* fixed a bug that would treat a multiarch image containing just one arch as a plain single arch image

## Changes in 0.4.1
* updated the base image used in this task
  * the new image contains an updated upload_rpm_manifest script with nvra and summary
    fields populated for each rpm item

## Changes in 0.4.0
* updated the base image used in this task

## Changes in 0.3.0
* updated the base image used in this task

## Changes in 0.2.1
* enabled verbose logging for the upload_rpm_manifest script

## Changes in 0.2.0
* updated the base image used in this task

## Changes in 0.1.2
* add support for production-internal and stage-internal

## Changes in 0.1.1
* multi-arch images are now properly supported
