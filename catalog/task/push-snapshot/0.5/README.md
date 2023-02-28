# push-snapshot

Tekton task to push snapshot images to an image registry using `skopeo copy`.

## Parameters

| Name           | Description                                                                                     | Optional | Default value |
|----------------|-------------------------------------------------------------------------------------------------|----------|---------------|
| mappedSnapshot | JSON string representing the Snapshot                                                           | No       | -             |
| tag            | Default tag to use if mapping entry does not contain a tag | Yes     | latest        |
| retries        | Retry copy N times                                                                              | Yes      | 0             |

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
