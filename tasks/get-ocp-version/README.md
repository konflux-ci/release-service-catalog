# get-ocp-version

Tekton task to collect OCP version tag from FBC fragment using `skopeo inspect`.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| fbcFragment | A FBC container Image | No | - |

## Changes since 0.2.0
- Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes since 0.1
 - update Tekton API to v1 