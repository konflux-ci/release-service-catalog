# sign-index-image

Creates an InternalRequest to sign an index image

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| requestJsonResults | The JSON result of the IIB build internal request | Yes | "{}" |
| targetIndex | targetIndex signing image | Yes | - |
| requestUpdateTimeout | Max seconds waiting for the status update| Yes | 360 |
| signingPipelineImage | An image with CLI tools needed for the signing | Yes | quay.io/redhat-isv/operator-pipelines-images:released |
| requester | Name of the user that requested the signing, for auditing purposes | No | - |
| configMapName | ConfigMap Name for this request | No | hacbs-signing-pipeline-config |
| pipelineRunName | The name of the Parent PipelineRun for this task | Yes | `ir-$(context.pipelineRun.name)` |
