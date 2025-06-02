# check-data-keys

Tekton task that validates data keys against a schema to ensure that all required keys for a system(s) are present and correctly formatted. The system(s) passed into the `systems` parameter become required. The schema validation also applies to all data passed into the `dataPath` parameter, meaning all the data keys must be allowed and formatted correctly.

For example, if `releaseNotes` is passed as a system and the data file does not have all the required
releaseNotes keys, the schema will give validation errors, and the task will fail.

Currently, `releaseNotes`, and `cdn` are the only supported systems.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value                                                                                                    |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|------------------------------------------------------------------------------------------------------------------|
| dataPath                | Path to the JSON string of the merged data to use                                                                          | No       |                                                                                                                  |
| systems                 | The systems to check that all data keys are present for                                                                    | Yes      | []                                                                                                               |
| schema                  | The URl to the schema                                                                                                      | Yes      | https://raw.githubusercontent.com/konflux-ci/release-service-catalog/refs/heads/development/schema/dataKeys.json |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                                                                                                            |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                                                                                                               |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                                                                                                               |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                                                                                                               | 
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                                                                                                               |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | $(workspaces.data.path)                                                                                          |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | ""                                                                                                               |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | ""                                                                                                               |

## Changes in 2.1.0
* Added compute resource limits

## Changes in 2.0.0
* This task now supports Trusted artifacts

## Changes in 1.0.2
* Strip the `.git/` suffix from the `schema` value if present. Some `taskGitUrl`s add this suffix which results in invalid schema files being passed

## Changes in 1.0.1
* Add `-L` option to curl command to follow redirects for schema download.
* Fixes README.md `schema` parameter description.

## Changes in 1.0.0
* Replacing the check with a schema validator

## Changes in 0.9.2
* Fixing checkton/shellcheck linting issues in the task and test

## Changes in 0.9.1
* The task would show failure output if a system with just one key was added (as cdn currently is)

## Changes in 0.9.0
* Added the cdn system

## Changes in 0.8.0
* Updated the base image used in this task

## Changes in 0.7.0
* Updated the base image used in this task

## Changes in 0.6.0
* Remove `dataPath` default value

## Changes in 0.5.0
* Add releaseNotes.product_stream to required keys

## Changes in 0.4.0
* Add releaseNotes.product_name and releaseNotes.product_version to required keys

## Changes in 0.3.0
* Replace advisory.spec references with releaseNotes key

## Changes in 0.1.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead
