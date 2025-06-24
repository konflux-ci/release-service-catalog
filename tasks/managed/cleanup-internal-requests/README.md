# cleanup-internal-requests

Tekton task to delete internal requests associated with a pipelinerun

## Parameters

| Name           | Description                                                                                                      | Optional | Default value |
|----------------|------------------------------------------------------------------------------------------------------------------|----------|---------------|
| pipelineRunUid | The uid of the current pipelineRun. It is only available at the pipeline level                                   | No       | -             |
