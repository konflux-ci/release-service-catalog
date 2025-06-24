# create-advisory-oci-artifact-task

Creates an oci artifact of an advisory given a Gitlab URL.

## Parameters

| Name                                            | Description                                                                                        | Optional | Default value                                         |
|-------------------------------------------------|----------------------------------------------------------------------------------------------------|----------|-------------------------------------------------------|
| advisory_url                                    | the url of the advisory                                                                            | No       | -                                                     |
| internalRequestPipelineRunName                  | Name of the PipelineRun that called this task                                                      | No       | -                                                     |
| trusted_artifacts_dockerconfig_json_secret_name | The name of the secret that contains to dockerconfig json to use for trusted artifact operations   | Yes      | quay-token-konflux-release-trusted-artifacts-secret   |  
