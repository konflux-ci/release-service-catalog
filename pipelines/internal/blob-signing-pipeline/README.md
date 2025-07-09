# blob-signing pipeline

Tekton pipeline for signing base64 blobs

## Parameters

| Name            | Description                                                                           | Optional | Default value                                                                         |
|-----------------|---------------------------------------------------------------------------------------|----------|---------------------------------------------------------------------------------------|
| pipeline_image  | An image with CLI tools needed for the signing                                        | Yes      | quay.io/redhat-isv/operator-pipelines-images:9ea90b42456fcdf66edf4b15c0c0487ba5fa3ee3 |
| blob            | Blob that needs to be signed                                                          | No       | -                                                                                     |
| requester       | Name of the user that requested the signing, for auditing purposes                    | No       | -                                                                                     |
| config_map_name | A config map name with configuration                                                  | Yes      | hacbs-signing-pipeline-config                                                         |
| taskGitUrl      | The url to the git repo where the release-service-catalog tasks to be used are stored | Yes      | https://github.com/konflux-ci/release-service-catalog.git                             |
| taskGitRevision | The revision in the taskGitUrl repo to be used                                        | No       | -                                                                                     |
