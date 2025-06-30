# create-advisory-oci-artifact-task

Creates an oci artifact of an advisory given a Gitlab URL.
The task will always exit 0 even if something fails. This is because the task result will not be
set if the task fails, and the task result should always be set and propagated back to the cluster
that creates the internal request. The success/failure is handled in the task creating the internal
request.

## Parameters

| Name                                            | Description                                                                                      | Optional | Default value                                       |
|-------------------------------------------------|--------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------|
| advisory_url                                    | the url of the advisory                                                                          | No       | -                                                   |
| internalRequestPipelineRunName                  | Name of the PipelineRun that called this task                                                    | No       | -                                                   |
| trusted_artifacts_dockerconfig_json_secret_name | The name of the secret that contains to dockerconfig json to use for trusted artifact operations | Yes      | quay-token-konflux-release-trusted-artifacts-secret |
