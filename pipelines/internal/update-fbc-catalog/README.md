# update-fbc-catalog pipeline

Tekton pipeline add/update FBC fragments to the FBC catalog by interacting with IIB service for File Based Catalogs

## Parameters

| Name                    | Description                                                                           | Optional | Default value                                             |
|-------------------------|---------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| iibServiceAccountSecret | Secret containing the credentials for IIB service                                     |   yes    | iib-service-account                                       |
| publishingCredentials   | Secret containing the publishing credentials used to fetch the image config           |   no     |                                                           |
| fbcFragment             | FBC fragment built by HACBS                                                           |   no     | -                                                         |
| fromIndex               | Index image (catalog of catalogs) the FBC fragment will be added to                   |   no     | -                                                         |
| buildTags               | List of additional tags the internal index image copy should be tagged with           |   yes    | '[]'                                                      |
| addArches               | List of arches the index image should be built for                                    |   yes    | '[]'                                                      |
| hotfix                  | Whether this build is a hotfix build                                                  |   yes    | false                                                     |
| stagedIndex             | Whether this build is a staged index build                                            |   yes    | false                                                     |
| buildTimeoutSeconds     | IIB Build Service timeout seconds                                                     |   no     | -                                                         |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks to be used are stored |   yes    | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                        |   no     | -                                                         |
