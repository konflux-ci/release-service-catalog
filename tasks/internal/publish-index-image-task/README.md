# publish-index-image-task

Tekton task to publish a built FBC index image using skopeo

## Parameters

| Name                  | Description                                   | Optional | Default value |
|-----------------------|-----------------------------------------------|----------|---------------|
| sourceIndex           | sourceIndex signing image                     | No       | -             |
| targetIndex           | targetIndex signing image                     | No       | -             |
| retries               | Number of skopeo retries                      | Yes      | 0             |
| publishingCredentials | The credentials used to access the registries | No       | -             |
| requestUpdateTimeout  | Max seconds waiting for the status update     | Yes      | 360           |
