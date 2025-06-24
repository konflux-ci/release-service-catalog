# request-advisory-oci-artifact

Tekton task to request the advisory content from gitlab as an oci artifact.

## Parameters

| Name             | Description                                                                                           | Optional | Default value |
|------------------|-------------------------------------------------------------------------------------------------------|----------|---------------|
| advisory_url     | the url of the advisory                                                                               | No       | -             |
| requestTimeout   | InternalRequest timeout                                                                               | Yes      | 2700          |
| pipelineRunUid   | The uid of the current pipelineRun. Used as a label value when creating internal requests             | No       | -             |  
| taskGitUrl       | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored | No       | -             |
| taskGitRevision  | The revision in the taskGitUrl repo to be used                                                        | No       | -             |  
