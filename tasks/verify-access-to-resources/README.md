# verify-access-to-resources

This Tekton task is used to verify access to various resources in the pipelines. It ensures that the necessary resources, such as the release, release plan, release plan admission, release service config and snapshot, are available and accessible. Additionally, it checks if internal requests can be created if `requireInternalServices` is set to `true`.

## Parameters

| Name                    | Description                                             | Optional | Default value |
|-------------------------|---------------------------------------------------------|----------|---------------|
| release                 | Namespace/name of the Release                           | No       | -             |
| releasePlan             | Namespace/name of the ReleasePlan                       | No       | -             |
| releasePlanAdmission    | Namespace/name of the ReleasePlanAdmission              | No       | -             |
| releaseServiceConfig    | Namespace/name of the ReleaseServiceConfig              | No       | -             |
| snapshot                | Namespace/name of the Snapshot                          | No       | -             |
| requireInternalServices | Whether to check if internal requests can be created    | Yes      | false         |

## Changes in 0.3.1
* Fix shellcheck/checkton linting issues in the task

## Changes in 0.3.0
* Added `requireInternalServices` parameter to determine if internal request checks are required.

## Changes in 0.2.0
* Updated the base image used in this task from `hacbs-release/cloud-builders` to `redhat-appstudio/release-service-utils` image
