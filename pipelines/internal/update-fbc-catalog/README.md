# update-fbc-catalog pipeline

Tekton pipeline add/update FBC fragments to the FBC catalog by interacting with IIB service for File Based Catalogs

## Parameters

| Name                    | Description                                                                           | Optional | Default value                                             |
|-------------------------|---------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| iibServiceAccountSecret | Secret containing the credentials for IIB service                                     | Yes      | iib-service-account                                       |
| publishingCredentials   | Secret containing the publishing credentials used to fetch the image config           | No       | -                                                         |
| fbcFragments            | FBC fragments built by Konflux as JSON array (e.g. ["fragment1", "fragment2"])        | No       | -                                                         |
| fromIndex               | Index image (catalog of catalogs) the FBC fragment will be added to                   | No       | -                                                         |
| targetIndex             | Target index is the pullspec the FBC catalog will be pushed to                        | No       | -                                                         |
| buildTags               | List of additional tags the internal index image copy should be tagged with           | Yes      | []                                                        |
| addArches               | List of arches the index image should be built for                                    | Yes      | []                                                        |
| hotfix                  | Whether this build is a hotfix build                                                  | Yes      | false                                                     |
| stagedIndex             | Whether this build is a staged index build                                            | Yes      | false                                                     |
| buildTimeoutSeconds     | IIB Build Service timeout seconds                                                     | No       | -                                                         |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks to be used are stored | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                        | No       | -                                                         |
