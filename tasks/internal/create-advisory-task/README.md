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
| contentType                    | The contentType of the release artifact. One of [image|binary|generic]                                 | Yes      | image         |
| config_map_name                | The name of the configMap that contains the signing key                                                | No       | -             |
| advisory_secret_name           | The name of the secret that contains the advisory creation metadata                                    | No       | -             |
| errata_secret_name             | The name of the secret that contains the errata service account metadata                               | No       | -             |
| internalRequestPipelineRunName | Name of the PipelineRun that called this task                                                          | No       | -             |
