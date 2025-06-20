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

## Changes in 1.2.2
* Add retry for skopeo inspect

## Changes in 1.2.1
* Increased memory limit from 128Mi to 512Mi

## Changes in 1.2.0
* Added compute resource limits

## Changes in 1.1.1
* adds equality check of `from_index` and `index_image` in `check_previous_build()`
  to determine if the build was a prod or a staging build

## Changes in 1.1.0
* adds new parameter `publishingCredentials`

## Changes in 1.0.2
* Fix an issue caused by the `indexImageDigests` result being multi line - now the digests are space-separated on one line

## Changes in 1.0.1
* fixes the case when an in_progress IIB build is not resumed;
* adds more unit tests for retry scenarios;
