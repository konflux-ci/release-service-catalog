# update-fbc-catalog pipeline

Tekton pipeline add/update FBC fragments to the FBC catalog by interacting with IIB service for File Based Catalogs

## Parameters

| Name                        | Description                                                                            | Optional | Default value                                             |
|-----------------------------|----------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| iibServiceAccountSecret     | Secret containing the credentials for IIB service                                      | Yes      | iib-service-account                                       |
| publishingCredentials       | Secret containing the publishing credentials used to fetch the image config            | No       | -                                                         |
| fbcFragments                | FBC fragments built by Konflux as JSON array (e.g. ["fragment1", "fragment2"])         | No       | -                                                         |
| fromIndex                   | Index image (catalog of catalogs) the FBC fragment will be added to                    | No       | -                                                         |
| buildTags                   | List of additional tags the internal index image copy should be tagged with            | Yes      | []                                                        |
| addArches                   | List of arches the index image should be built for                                     | Yes      | []                                                        |
| mustPublishIndexImage       | Whether the index image should be published (pre-determined by prepare-fbc-parameters) | Yes      | false                                                     |
| mustOverwriteFromIndexImage | Whether to overwrite the from index image (pre-determined by prepare-fbc-parameters)   | Yes      | false                                                     |
| buildTimeoutSeconds         | Timeout seconds to receive the build state                                             | Yes      | 3600                                                      |
| taskGitUrl                  | The url to the git repo where the release-service-catalog tasks to be used are stored  | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision             | The revision in the taskGitUrl repo to be used                                         | No       | -                                                         |
