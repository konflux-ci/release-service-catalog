# publish-index-image

Publish a built FBC index image using skopeo

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| targetIndex | targetIndex signing image | No | |
| inputDataFile | Optional file to read data from | No | |
| retries | Number of skopeo retries | Yes | "0" |
| publishingCredentials | The credentials used to access the registries | Yes | "fbc-publishing-credentials" |
| requestUpdateTimeout | Max seconds waiting for the status update | Yes | 360 |

## Changelog

### changes since 0.2
- update Tekton API to v1

### changes since 0.1
- adds `inputDataFile` parameter to read the image source from it
