# publish-index-image

Publish a built FBC index image using skopeo

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| requestJsonResults | The JSON result of the IIB build internal request | No | |
| targetIndex | targetIndex signing image | No | |
| retries | Number of skopeo retries | Yes | "0" |
| publishingCredentials | The credentials used to access the registries | Yes | "fbc-publishing-credentials" |
| requestUpdateTimeout | Max seconds waiting for the status update | Yes | 360 |

