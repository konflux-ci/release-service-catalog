# blob-signing pipeline

Tekton pipeline for signing base64 blobs

## Parameters

| Name            | Description                                                                           | Optional | Default value                                                                     |
|-----------------|---------------------------------------------------------------------------------------|----------|-----------------------------------------------------------------------------------|
| pipeline_image  | An image with CLI tools needed for the signing                                        | Yes      | quay.io/konflux-ci/release-service-utils:9d57cd95e60f0c61a118fe9261f5941815d33469 |
| blob            | Blob that needs to be signed                                                          | No       | -                                                                                 |
| requester       | Name of the user that requested the signing, for auditing purposes                    | No       | -                                                                                 |
| config_map_name | A config map name with configuration                                                  | Yes      | hacbs-signing-pipeline-config                                                     |
| taskGitUrl      | The url to the git repo where the release-service-catalog tasks to be used are stored | Yes      | https://github.com/konflux-ci/release-service-catalog.git                         |
| taskGitRevision | The revision in the taskGitUrl repo to be used                                        | No       | -                                                                                 |
