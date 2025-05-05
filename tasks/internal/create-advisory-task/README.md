# create-advisory-task

Pushes an advisory yaml to a Git repository. The task will always exit 0 even if something fails. This is because the task result
will not be set if the task fails, and the task result should always be set and propagated back to the cluster that creates the
internal request. The success/failure is handled in the task creating the internal request.

## Parameters

| Name                           | Description                                                                                            | Optional | Default value |
|--------------------------------|--------------------------------------------------------------------------------------------------------|----------|---------------|
| advisory_json                  | String containing a JSON representation of the advisory data (e.g. '{"product_id":123,"type":"RHSA"}') | No       | -             |
| application                    | Application being released                                                                             | No       | -             |
| origin                         | The origin workspace where the release CR comes from. This is used to determine the advisory path      | No       | -             |
| config_map_name                | The name of the configMap that contains the signing key                                                | No       | -             |
| advisory_secret_name           | The name of the secret that contains the advisory creation metadata                                    | No       | -             |
| errata_secret_name             | The name of the secret that contains the errata service account metadata                               | No       | -             |
| internalRequestPipelineRunName | Name of the PipelineRun that called this task                                                          | No       | -             |

## Changes in 1.2.0
* Allow setting of custom advisory live id
  * If `live_id` is set in the advisory json, use that instead of requesting one from Errata Tool API

## Changes in 1.1.3
* Change the `advisory_url` result to use link to customer portal instead of git repo

## Changes in 1.1.2
* Fixes an error introduced in 1.0.0 which affected new advisories.

## Changes in 1.1.1
* Optimized advisory matching with early exit when all images are already released.

## Changes in 1.1.0
* Update base image
  * New base image contains a new version of the advisory apply template script that render jinja expressions in
    releaseNotes field values.

## Changes in 1.0.0
* Make create advisory task idempotent

## Changes in 0.12.0
* Updated logging
  * Use a STDERR_FILE and tail it into the `result` task result so that the calling task has better
    visibility into what failed
  * Add internalRequestPipelineRunName as a parameter to return as a task result and also one for
    InternalRequestTaskRunName

## Changes in 0.11.1
* Update base image
  * New base image contains a new version of the advisory template that includes severity
