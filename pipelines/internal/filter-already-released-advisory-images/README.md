# filter-already-released-advisory-images pipeline

This pipeline filters out images from a snapshot that have already been published in advisories.  

## Parameters

| Name                 | Description                                                                                       | Optional | Default value                                             |
|----------------------|---------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| snapshot             | Base64 string of gzipped JSON representation of the snapshot spec                                 | No       | -                                                         |
| origin               | The origin workspace where the release CR comes from. This is used to determine the advisory path | No       | -                                                         |
| advisory_secret_name | The name of the secret that contains the advisory creation metadata                               | No       | -                                                         |
| taskGitUrl           | The url to the git repo where the release-service-catalog tasks to be used are stored             | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision      | The revision in the taskGitUrl repo to be used                                                    | No       | -                                                         |
