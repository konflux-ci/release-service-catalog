# filter-already-released-advisory-images-task

This internal Tekton task filters out images from a snapshot if they have already
been published in an advisory stored in a GitLab repository.
It returns a list of component names that still need to be released (i.e., not found in any advisory).

## Parameters

| Name                           | Description                                                                                            | Optional | Default value |
|--------------------------------|--------------------------------------------------------------------------------------------------------|----------|---------------|
| snapshot_json                  | String containing the full JSON representation of the snapshot spec                                    | No       | -             |
| origin                         | The origin workspace for the release CR (used to locate advisories)                                    | No       | -             |
| advisory_secret_name           | Name of the secret containing GitLab repo and token information                                        | No       | -             |
| internalRequestPipelineRunName | Name of the PipelineRun that called this task                                                          | No       | -             |
