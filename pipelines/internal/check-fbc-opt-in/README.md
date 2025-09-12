# check-fbc-opt-in pipeline

Internal pipeline to check FBC opt-in status for container images via Pyxis.
Uses the simplified check-fbc-opt-in task to query Pyxis for each provided container image.

## Parameters

| Name            | Description                                                                                           | Optional | Default value |
|-----------------|-------------------------------------------------------------------------------------------------------|----------|---------------|
| containerImages | JSON array of container images to check for FBC opt-in status                                         | No       | -             |
| pyxisSecret     | Name of secret which contains the required credentials for authentication to pyxis                    | No       | -             |
| pyxisServer     | Pyxis server to use                                                                                   | Yes      | production    |
| taskGitUrl      | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored | No       | -             |
| taskGitRevision | The revision in the taskGitUrl repo to be used                                                        | No       | -             |
