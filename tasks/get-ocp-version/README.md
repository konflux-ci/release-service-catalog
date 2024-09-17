# get-ocp-version

Tekton task to collect OCP version tag from FBC fragment using `skopeo inspect`.

## Parameters

| Name        | Description           | Optional | Default value |
|-------------|-----------------------|----------|---------------|
| fbcFragment | A FBC container Image | No       | -             |


## Changes in 0.5.1
* Task updated to handle multi-arch fbc fragments

## Changes in 0.5.0
* Updated the base image used in this task

## Changes in 0.4.0
* Updated the base image used in this task

## Changes in 0.2.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 0.1
* update Tekton API to v1 
