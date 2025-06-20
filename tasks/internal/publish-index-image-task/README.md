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

## Changes in 0.3.1
* Add retry for skopeo inspect

## Changes in 0.3.0
* Added compute resource limits

## Changes in 0.2.0
* Make publish index image task idempotent
