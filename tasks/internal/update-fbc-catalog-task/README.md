# update-fbc-catalog task

Tekton task to submit a IIB build request to add/update a fbc-fragment to an index image

| Name                    | Description                                                                  | Optional | Default value |
| ----------------------- | ---------------------------------------------------------------------------- | -------- | ------------- |
| fbcFragment             | FBC fragment built by HACBS                                                  | No       | -             |
| fromIndex               | Index image (catalog of catalogs) the FBC fragment will be added to          | No       | -             |
| buildTags               | List of additional tags the internal index image copy should be tagged with. | No       | -             |
| addArches               | List of arches the index image should be built for.                          | No       | -             |
| buildTimeoutSeconds     | Timeout seconds to receive the build state                                   | Yes      | "300"         |
| iibServiceAccountSecret | Secret with IIB credentials to be used                                       | No       | -             |
| publishingCredentials   | Secret containing the publishing credentials used to fetch the image config  | No       | -             |
| hotfix                  | Whether this build is a hotfix build                                         | Yes      | "false"       |
| stagedIndex             | Whether this build is for a staged index build                               | Yes      | "false"       |
