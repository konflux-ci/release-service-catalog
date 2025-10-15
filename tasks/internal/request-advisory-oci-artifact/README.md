# request-advisory-oci-artifact

Tekton task to request the advisory content from gitlab as an oci artifact.

## Parameters

| Name                 | Description                                                                                           | Optional | Default value |
|----------------------|-------------------------------------------------------------------------------------------------------|----------|---------------|
| advisory_url         | The advisory url                                                                                      | No       | -             |
| requestTimeout       | InternalRequest timeout                                                                               | Yes      | 2700          |
| pipelineRunUid       | The uid of the current pipelineRun. Used as a label value when creating internal requests             | No       | -             |
| taskGitUrl           | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored | No       | -             |
| taskGitRevision      | The revision in the taskGitUrl repo to be used                                                        | No       | -             |
| caTrustConfigMapName | The name of the ConfigMap to read CA bundle data from                                                 | Yes      | trusted-ca    |
| caTrustConfigMapKey  | The name of the key in the ConfigMap that contains the CA bundle data                                 | Yes      | ca-bundle.crt |
