# push-snapshot

Tekton task to push snapshot images to an image registry using `cosign copy`.

## Parameters

| Name                 | Description                                                               | Optional | Default value        |
|----------------------|---------------------------------------------------------------------------|----------|----------------------|
| snapshotPath         | Path to the JSON string of the mapped Snapshot spec in the data workspace | No       | -                    |
| dataPath             | Path to the JSON string of the merged data to use in the data workspace   | No       | -                    |
| resultsDirPath       | Path to results directory in the data workspace                           | No       | -                    |
| retries              | Retry copy N times                                                        | Yes      | 0                    |
| caTrustConfigMapName | The name of the ConfigMap to read CA bundle data from                     | Yes      | trusted-ca           |
| caTrustConfigMapKey  | The name of the key in the ConfigMap that contains the CA bundle data     | Yes      | ca-bundle.crt        |

## Changes in 6.3.0
* Add support for custom CA cert in push-snapshot task

## Changes in 6.2.1
* Create new docker config for each cosign call
  * It only contains entries for the source and destination repos
  * This is to fix a bug with partial oci auth matches

## Changes in 6.2.0
* Updated the base image used in this task

## Changes in 6.1.0
* added support for OCI artifacts.

## Changes in 6.0.0
* The `images` section of the data key is no longer supported. Tags, timestamp format, and push source container
  options are now specified in each component or in `mapping.defaults`
* The `commonTags` result is removed
* The task fails if any component has no tags associated with it

## Changes in 5.0.0
* The task now writes pushed image details to a results json file in the workspace

## Changes in 4.7.0
* Updated the base image used in this task

## Changes in 4.6.0
* Updated the base image used in this task

## Changes in 4.5.0
* Tag expansion is removed in favor of doing it in the apply-mapping task

## Changes in 4.4.0
* Added support for component specific tags
  * Each component in the mapping can specify a tags array
  * A defaults section can also be provided in the mapping
  * The supported variables will be replaced in the passed tags
  * The old functionality remains. The new tag functionality is only used if provided. In version 5.0.0, the old
    functionality will be removed. The new tag functionality has priority over the old style.

## Changes in 4.3.0
* When pushing source containers, the origin is now determined using `$repo:${digest}.src` instead of `$repo:${git_sha}.src`
  that was used previously. This follows a change in the build service.
  * We also added a new push of the source container to `$repo:${digest}.src`.
* Fixed a bug when pushing source containers where previously we would never skip a push even if the destination container
  already existed, because we were comparing the binary image digest instead of the source container one.

## Changes in 4.2.0
* remove `dataPath` and `snapshotPath` default values

## Changes in 4.1.2
* Fixed bug that causes `arch_json` to be empty after setting it
* Update release-service-utils image

## Changes in 4.1.1
* Absorb change in refactored get-image-architectures script

## Changes in 4.1.0
* Add `--override-arch` to `skopeo` calls to avoid breaking the task when the component's container image
  architecture is different from the pod the task runs on.

## Changes in 4.0.1
* Incorrect floatingTag replaced with $floatingTag

## Changes in 4.0.0
* floatingTag is replaced by floatingTags in the RPA's data.images field
  * A list of floating tags is accepted instead of a single string. The logic remains unchanged, with each
    provided floating tag treated as the single one was previously
* Digest checking behavior was modified
  * Previously, a push only happened if the containerImage did not exist at $repository:$tag. This is flawed
    as we push to multiple tags (git, sha, timestamp...) yet we only checked against the default tag. Now,
    every push_image call has a check to see if the image already exists at the destination digest
* For source containers, an image is now pushed to $floatingTag-source as well as the existing
  $floatingTag-$timestamp-source location

## Changes in 3.0.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 2.0.0
* Rename tagPrefix to floatingTag
  * The optional parameter provided in RPA's data.images changes its name to clarify its meaning

## Changes in 1.2.0
* Push to floating tags when tagPrefix is set
  * In addition to pushing to $prefix-$timestamp, we now also push to $prefix
  * Rename result commonTag to commonTags and save both tags in it

## Changes in 1.1.1
* The pushSourceContainer parameter was removed in favor of reading it from the data.json

## Changes in 1.1.0
* The source container source pullspec was updated to use a git sha tag instead of the image digest.

## Changes in 1.0.1
* The new functionality is added to publish source containers to a given target
  * A new parameter exists called pushSourceContainer to enable/disable the source container push,
    the value is set to false by default
  * a new tag `sourceTag = <prefix>-<integer timestamp>-source` is added for source container push

## Changes in 1.0.0
* Fixed bug where the defaultTag was not being properly read

## Changes in 0.12
* The tag parameters are now pulled from the images key in the data json
  * A new parameter exists called dataPath that specifies the path to the JSON string of merged data in the workspace
  * tag, tagPrefix, timestampFormat, addGitShaTag, addSourceShaTag, and addTimestampTag are no longer task parameters
    * They are now pulled from the data json. The boolean ones accept "true" and "false"
    * Their defaults were kept, namely addTimestampTag defaults to true and addGitShaTag and addSourceShaTag default
      to true

## Changes in 0.11
* Adds `tagPrefix` parameter
* The task now generates a tag in <prefix>-<timestamp> format when `tagPrefix` length is non zero

## Changes in 0.10
* Update Tekton API to v1

## Changes in  0.9
* `addGitShaTag` now creates 2 tags:
  * tag composed of a shortened git sha based on first seven characters of sha (existing functionality)
  * tag composed of complete sha (new functionality)

## Changes in 0.8
* `cosign copy` replaces `skopeo copy` so the signatures and attestations are also copied
  * As part of this change, the image used in this task was updated to the release-utils image
  * Some flags that exist for `skopeo copy`, but not for `cosign copy` were dropped, but the functionality
    seems to be unchanged

## Changes in 0.7
* mappedSnapshot parameter was removed and snapshotPath parameter was added
  * Instead of passing a json string representing the snapshot, the snapshot spec should exist in the data workspace
    in the filename provided by snapshotPath

## Changes in 0.6
* Only the first seven characters of the git sha are used when creating the sha tag in Quay

## Changes in 0.5
* JSON data interpretation logic was switched from creating a bash array to using `jq`
* Parameter `addShaTag` was renamed to `addSourceShaTag`
* Parameter `addGitShaTag` was added. This parameter specifies whether or not to additionally push a tag with the
  git sha for each image in the snapshot
* The syntax for `taskRef.bundle` and `pipelineRef.bundle` is deprecated,
  bundles resolver is used with new format.

## Changes in 0.4

* Parameter `addShaTag` was added. This parameter specifies whether or not to additionally push a tag with the
  sha for each image in the snapshot
* Parameter `addTimestampTag` was added. This parameter specifies whether or not to additionally push a tag with the
  current timestamp for each image in the snapshot
* `skopeo inspect` has the `--no-tags` flag added to prevent timeouts on large repos

## Changes in 0.3

* Default tag to use will default to `tag` parameter

## Changes in 0.2

* Base image was changed from `release-utils` to `release-base-image`

## Changes in 0.1 (milestone-8)

* Task `samples/sample_push-application-snapshot_TaskRun.yaml` was renamed to `samples/sample_push-snapshot_TaskRun.yaml`
* Task `push-application-snapshot` was renamed to `push-snapshot`
* Task `push-snapshot` was changed
  * Task parameter `mappedApplicationSnapshot` value was changed
    * old: $(params.mappedApplicationSnapshot)
    * new: $(params.mappedSnapshot)
