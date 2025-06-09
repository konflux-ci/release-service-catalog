# create-pyxis-image

Tekton task that pushes metadata to Pyxis for all container images contained in a snapshot that is the
result of the `apply-mapping` task. It first extracts the containerImages from the snapshot, then runs
`skopeo inspect` on each, before finally pushing metadata to Pyxis.

The relative path of the pyxis.json file in the data workspace is output as a task result named
`pyxisDataPath`.

## Parameters

| Name                    | Description                                                                                                                                                                                                                                                                                                                                                                                                 | Optional | Default value           |
|-------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|-------------------------|
| server                  | The server type to use. Options are 'production','production-internal,'stage-internal' and 'stage'.                                                                                                                                                                                                                                                                                                         | No       | ""                      |
| pyxisSecret             | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys: key and cert                                                                                                                                                                                                                                                                                                           | No       | -                       |
| certified               | If set to true, the images will be marked as certified in their Pyxis entries                                                                                                                                                                                                                                                                                                                               | Yes      | false                   |
| isLatest                | If set to true, the images will have a latest tag added with their Pyxis entries                                                                                                                                                                                                                                                                                                                            | Yes      | false                   |
| rhPush                  | If set to true, an additional entry will be created in ContainerImage.repositories with the registry and repository fields converted to use Red Hat's official registry. E.g. a mapped repository of "quay.io/redhat-pending/product---my-image" will be converted to use registry "registry.access.redhat.com" and repository "product/my-image". Also, this repository entry will be marked as published. | Yes      | false                   |
| snapshotPath            | Path to the JSON string of the mapped Snapshot spec in the data workspace                                                                                                                                                                                                                                                                                                                                   | No       | -                       |
| dataPath                | Path to the JSON string of the merged data to use in the data workspace                                                                                                                                                                                                                                                                                                                                     | No       |                         |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                                                                                                                                                                                                                                                                                                   | Yes      | empty                   |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire                                                                                                                                                                                                                                                                                  | Yes      | 1d                      |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                                                                                                                                                                                                                                                                                                      | Yes      | ""                      |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                                                                                                                                                                                                                                                                                                             | Yes      | ""                      |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                                                                                                                                                                                                                                                                                                         | Yes      | ""                      |
| dataDir                 | The location where data will be stored                                                                                                                                                                                                                                                                                                                                                                      | Yes      | $(workspaces.data.path) |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                                                                                                                                                                                                                                                                                                       | No       | ""                      |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                                                                                                                                                                                                                                                                                                              | No       | ""                      |

## Changes in 5.0.0
* Replace `.pyxis.skipLayers` with `.pyxis.includeLayers`
  * We want to skip the layer details when creating images in Pyxis by default,
    so to include it in the future, the data will need to set
    `.pyxis.includeLayers=true` explicitly

## Changes in 4.1.0
* Remove logic to determine dockerfile name
  * This logic was added as a temporary fix until it's fixed on build side. And now it is

## Changes in 4.0.0
* This task now supports Trusted artifacts

## Changes in 3.8.5
* Bump the utils image user in this task
* cleanup_tags script is now called with --repository parameter

## Changes in 3.8.4
* Bump the utils image used in this task
  * Fix an error if there are no tags for a repository in an existing
    ContainerImage object in Pyxis
    * The previous fix works for one scenario, but not another. Now it works
      for both

## Changes in 3.8.3
* Bump the utils image used in this task
  * Fix an error if there are no tags for a repository in an existing
    ContainerImage object in Pyxis
    * The previous fix didn't work

## Changes in 3.8.2
* Bump the utils image used in this task
  * Fix an error if there are no tags for a repository in an existing
    ContainerImage object in Pyxis

## Changes in 3.8.1
* Bump the utils image used in this task
  * The `get-image-architectures` script now uses `set -e` so that it fails
    if a `skopeo` or `oras` call fails
* Modify the task script to make it fail if `get-image-architectures` fails
  and add a test for that

## Changes in 3.8.0
* Bump the utils image used in this task
  * Clair-wrapper is now ready to work with the changes introduced previously and
    reverted in 3.7.0, so move back to the newer utils image

## Changes in 3.7.0
* Revert image back to the version from 3.5.0
  * The new image contained two things:
    * New functionality to update image tags
    * It stopped creating a second quay.io repository entry in Pyxis
  * It turns out the second thing breaks clair-wrapper, so revert the change
    until clair-wrapper is modified

## Changes in 3.6.0
* Bumped the utils image used in this task
  * The updated image contains changes in create_container_image python script to enable the use case of updating tags when releasing the same image again

## Changes in 3.5.0
* Added mandatory `dataPath` task parameter
  * The data file can now contain `.pyxis.skipLayers` flag. If true, image layer information
    is deleted before calling the `create_container_image` script

## Changes in 3.4.4
* Bumped the utils image used in this task
  * The updated image contains refactoring of the create_container_image python script

## Changes in 3.4.3
* Updated the base image used in this task
  * The previous update changed the output of the create_container_image script
    that the task relies on. Now it's changed back.
* Made parsing of the image id more robust
  * Now it will work even if it's emitted more than once

## Changes in 3.4.2
* Updated the base image used in this task
  * The new image supports adding a new repository entry to the ContainerImage
    object in Pyxis if it already exists, but doesn't contain the repository
    entry yet
    * The use case is that an image was already released to one repository,
      but we may want to release it to another repository

## Changes in 3.4.1
* Fixed format of uncompressed layer list, prepending sha256:

## Changes in 3.4.0
* Added support for uploading uncompressed layer information to pyxis

## Changes in 3.3.4
* Properly expand platform variables for oras args

## Changes in 3.3.3
* Fixed linting issues in create-pyxis-image task

## Changes in 3.3.2
* Fixed fetching of Dockerfile oci artifact
  * The filename can be different than Dockerfile which is what we would expect
  * Now we get the filename from the manifest

## Changes in 3.3.1
* Fixed fetching of Dockerfile oci artifact
  * The pull spec is composed from the digest, but we need to replace `:` with `-`

## Changes in 3.3.0
* Updated the base image used in this task
  * The new image supports the --dockerfile cli argument for create_container_image
* Added support for Dockerfile upload to Pyxis

## Changes in 3.2.0
* Updated the base image used in this task

## Changes in 3.1.0
* added support for OCI artifacts.

## Changes in 3.0.0
* `dataPath` and `commonTags` parameters removed
  * These were only used for determining the tags to create the pyxis image with. These now come from the individual
    component entries in the snapshot spec file

## Changes in 2.8.0
* Updated the base image used in this task

## Changes in 2.7.1
* Only run the cleanup_tags script to clean up tags from previous images if rhPush=true
  * The script expects to find a registry.access.redhat.com repository entry for the image
    (which is only created if rhPush=true), so it would fail for images that do not have one.
* Use set -e for the step script. Without it, the script would carry on even if something failed along the way,
  e.g. if the cleanup_tags script failed because of Pyxis issues, we would still continue onto the next
  iteration in the loop. We should fail the task in this case.

## Changes in 2.7.0
* Updated the base image used in this task

## Changes in 2.6.1
* For each image that is created in Pyxis, the task will now also remove
  all its tags from all previous images
  * This is done via a new script called cleanup_tags from the utils image

## Changes in 2.6.0
* containerImage is no longer saved in the pyxis.json entries
  * This was already saved in pyxis.json per component, it doesn't need to be duplicated in the pyxisImages keys
* os is now saved to the pyxis.json pyxisImages entries

## Changes in 2.5.0
* The task now looks for tags in each component of the snapshot spec file and uses them instead of commonTags if any
  exist

## Changes in 2.4.0
* containerImageIDs result is removed as the data is present in pyxis.json that is written to the workspace
* the containerImage is now saved in the pyxis.json entries
* the pyxis.json file is saved in the same subdirectory as the passed snapshot file

## Changes in 2.3.0
* remove `dataPath` and `snapshotPath` default values

## Changes in 2.2.2
* Support populating multiarch image entities correctly

## Changes in 2.2.1
* Add support for server types of production-internal and stage-internal

## Changes in 2.2.0
* Add feature of pushing multi architecture images metadata to Pyxis

## Changes in 2.0.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 1.2.0
* Create a floating tag when tagPrefix is set
  * This is in addition to the tag tagPrefix-timestamp a.k.a. commonTag that we create in Pyxis now
* Update image used in the task
  * The new image supports multiple tags in the create_pyxis_image Python script

## Changes in 1.1.2
* Update image used in the task
  * When rhPush is true, now we'll create two entries in ContainerImage.repositories - one is the normal one and the other
    is the special one with registry="registry.access.redhat.com"

## Changes in 1.1.1
* Use the image digest when doing skopeo inspect
  * Without a digest, the `latest` tag was assumed. But if it was missing, the command would fail

## Changes in 1.1.0
* Update image used in the task
  * The new image contains fix for missing image_id field when creating the Pyxis Container Image object

## Changes in 1.0.0
* Add optional `rhPush` parameter
  * This will be used in the `rh-push-to-registry-redhat-io` to use the proper `registry` and `repository` values when
    creating the Container Image object in Pyxis. Also, the image will be marked as published.
* Add optional `commonTag` parameter
  * If set, the `tag` in the Pyxis Container Image object will be set to it

## Changes in 0.5
* The tag parameter is removed
  * The default tag is now provided by the 'images.defaultTag' key in the data JSON file as the pipeline parameter will
    no longer be passed.
  * dataPath parameter to point to the data JSON file in the data workspace was added.

## Changes in 0.4
* Update Tekton API to v1

## Changes in 0.3
* mappedSnapshot parameter was removed and snapshotPath parameter was added
  * Instead of passing a json string representing the snapshot, the snapshot spec should exist in the data workspace
    in the filename provided by snapshotPath.

## Changes in 0.2
* Use tag present in mapping file if present.
* The syntax for `taskRef.bundle` and `pipelineRef.bundle` is deprecated,
  bundles resolver is used with new format.

## Changes in 0.1
* Fix for incorrect snapshot param.
