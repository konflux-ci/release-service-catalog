# get-iib-builds-load pipeline

Internal pipeline to get the number of in-progress IIB builds for each given from_index.
Used by the fbc-release e2e test to pick the least-loaded OCP versions.

## Parameters

| Name            | Description                                                                                           | Optional | Default value |
|-----------------|-------------------------------------------------------------------------------------------------------|----------|---------------|
| fromIndexes     | JSON array of from_index pullspecs to get the in-progress build count for                             | No       | -             |
| user            | IIB user whose in-progress builds are counted                                                         | No       | -             |
| taskGitUrl      | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored | No       | -             |
| taskGitRevision | The revision in the taskGitUrl repo to be used                                                        | No       | -             |
