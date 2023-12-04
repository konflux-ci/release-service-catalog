# publish-index-image

Publish a built FBC index image using skopeo

## Parameters

| Name           | Description                                                             | Optional | Default value |
|----------------|-------------------------------------------------------------------------|----------|---------------|
| dataPath       | Path to the JSON string of the merged data to use in the data workspace | Yes      | data.json     |
| sourceIndex    | Pullspec to pull the image from                                         | No       |               |
| targetIndex    | Pullspec to push the image to                                           | No       |               |
| retries        | Number of skopeo retries                                                | Yes      | 0             |
| requestTimeout | Max seconds waiting for the status update                               | Yes      | 360           |
| buildTimestamp | Build timestamp for the publishing image                                | No       |               |

## Changelog

### Changes in 2.0.0
- Add the parameter `buildTimestamp` to push also a timestamp-based tag

### Changes in 1.0.0
- Refactor to use the `internal-request` script

### Changes since 0.3.0
- Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

### changes since 0.2
- update Tekton API to v1

### changes since 0.1
- adds `inputDataFile` parameter to read the image source from it
