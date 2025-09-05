# update-fbc-catalog-task

Tekton task to submit a IIB build request to add/update fbc-fragments to an index image

## Parameters

| Name                    | Description                                                                    | Optional | Default value |
|-------------------------|--------------------------------------------------------------------------------|----------|---------------|
| fbcFragments            | FBC fragments built by Konflux as JSON array (e.g. ["fragment1", "fragment2"]) | No       | -             |
| fromIndex               | Index image (catalog of catalogs) the FBC fragment will be added to            | No       | -             |
| targetIndex             | Target index is the pullspec the FBC catalog will be pushed to                 | No       | -             |
| buildTags               | List of additional tags the internal index image copy should be tagged with    | No       | -             |
| addArches               | List of arches the index image should be built for                             | No       | -             |
| buildTimeoutSeconds     | Timeout seconds to receive the build state                                     | Yes      | 300           |
| iibServiceAccountSecret | Secret with IIB credentials to be used                                         | No       | -             |
| publishingCredentials   | Secret containing the publishing credentials used to fetch the image config    | No       | -             |
| hotfix                  | Whether this build is a hotfix build                                           | Yes      | false         |
| stagedIndex             | Whether this build is for a staged index build                                 | Yes      | false         |
