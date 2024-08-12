# check-data-keys

Tekton task to check that all required information is present in the data file in order to use the
specified system(s). If any required keys are missing, the task will fail.

For example, if `releaseNotes` is passed as a system and the data file does not have all the required
releaseNotes keys, the task will fail.

Currently, `releaseNotes`, and `cdn` are the only supported systems.

## Parameters

| Name     | Description                                             | Optional | Default value |
|----------|---------------------------------------------------------|----------|---------------|
| dataPath | Path to the JSON string of the merged data to use       | No       |               |
| systems  | The systems to check that all data keys are present for | Yes      | []            |

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
