# simple-signing pipeline

Tekton pipeline for simple signing. It is meant to be used by the rh-sign-image task, not as a standalone managed pipeline.

## Parameters

| Name            | Description                                                                                            | Optional | Default value                                             |
|-----------------|--------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| pipeline_image  | An image with CLI tools needed for the signing.                                                        | Yes      | quay.io/redhat-isv/operator-pipelines-images:released     |
| manifest_digest | Manifest digest for the signed content, usually in the format sha256:xxx                               | No       | -                                                         |
| reference       | Docker reference for the signed content, e.g. registry.redhat.io/redhat/community-operator-index:v4.9  | No       | -                                                         |
| requester       | Name of the user that requested the signing, for auditing purposes                                     | No       | -                                                         |
| config_map_name | A config map name with configuration                                                                   | Yes      | hacbs-signing-pipeline-config                             |
| taskGitUrl      | The url to the git repo where the release-service-catalog tasks to be used are stored                  | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision | The revision in the taskGitUrl repo to be used                                                         | No       | -                                                         |
