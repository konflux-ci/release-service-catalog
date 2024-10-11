# check-data-keys

Tekton task that validates data keys against a schema to ensure that all required keys for a system(s) are present and correctly formatted. The system(s) passed into the `systems` parameter become required. The schema validation also applies to all data passed into the `dataPath` parameter, meaning all the data keys must be allowed and formatted correctly.

For example, if `releaseNotes` is passed as a system and the data file does not have all the required
releaseNotes keys, the schema will give validation errors, and the task will fail.

Currently, `releaseNotes`, and `cdn` are the only supported systems.

## Parameters

| Name     | Description                                             | Optional | Default value |
|----------|---------------------------------------------------------|----------|---------------|
| dataPath | Path to the JSON string of the merged data to use       | No       |               |
| systems  | The systems to check that all data keys are present for | Yes      | []            |
| schema   | The URl to the schema                                   | Yes      | https://github.com/konflux-ci/release-service-catalog/blob/production/schema/dataKeys.json |

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
