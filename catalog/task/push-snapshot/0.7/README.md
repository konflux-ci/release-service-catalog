# push-snapshot

Tekton task to push snapshot images to an image registry using `skopeo copy`.

## Parameters

| Name            | Description                                                                                     | Optional | Default value |
|-----------------|-------------------------------------------------------------------------------------------------|----------|---------------|
| mappedSnapshot  | JSON string representing the Snapshot                                                           | No       | -             |
| tag             | Default tag to use if mapping entry does not contain a tag                                      | Yes      | latest        |
| retries         | Retry copy N times                                                                              | Yes      | 0             |
| addGitShaTag    | Also push a tag with the git sha for each image in the Snapshot                                 | Yes      | true          |
| addSourceShaTag | Also push a tag with the source sha for each image in the Snapshot                              | Yes      | true          |
| addTimestampTag | Also push a tag with the current timestamp for each image in the Snapshot                       | Yes      | false         |

## Changes since 0.6
* Only the first seven characters of the git sha are used when creating the sha tag in Quay

## Changes since 0.5
* JSON data interpretation logic was switched from creating a bash array to using `jq`
* Parameter `addShaTag` was renamed to `addSourceShaTag`
* Parameter `addGitShaTag` was added. This parameter specifies whether or not to additionally push a tag with the
  git sha for each image in the snapshot
* The syntax for `taskRef.bundle` and `pipelineRef.bundle` is deprecated,
  bundles resolver is used with new format.

## Changes since 0.4

* Parameter `addShaTag` was added. This parameter specifies whether or not to additionally push a tag with the
  sha for each image in the snapshot
* Parameter `addTimestampTag` was added. This parameter specifies whether or not to additionally push a tag with the
  current timestamp for each image in the snapshot
* `skopeo inspect` has the `--no-tags` flag added to prevent timeouts on large repos

## Changes since 0.3

* Default tag to use will default to `tag` parameter

## Changes since 0.2

* Base image was changed from `release-utils` to `release-base-image`

## Changes since 0.1 (milestone-8)

* Task `samples/sample_push-application-snapshot_TaskRun.yaml` was renamed to `samples/sample_push-snapshot_TaskRun.yaml`
* Task `push-application-snapshot` was renamed to `push-snapshot`
* Task `push-snapshot` was changed
  * Task parameter `mappedApplicationSnapshot` value was changed
    * old: $(params.mappedApplicationSnapshot)
    * new: $(params.mappedSnapshot)
