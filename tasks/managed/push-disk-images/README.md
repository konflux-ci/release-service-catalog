# push-disk-images

Tekton task to push disk images via an InternalRequest to Exodus CDN in addition to Developer Portal.
The environment to use is pulled from the `cdn.env` key in the data file.

## Parameters

| Name                     | Description                                                                               | Optional | Default value |
|--------------------------|-------------------------------------------------------------------------------------------|----------|---------------|
| snapshotPath             | Path to the JSON file of the Snapshot spec in the data workspace                          | No       | -             |
| dataPath                 | Path to data JSON in the data workspace                                                   | No       | -             |
| pipelineRunUid           | The uid of the current pipelineRun. Used as a label value when creating internal requests | No       | -             |
| resultsDirPath           | Path to results directory in the data workspace                                           | No       | -             |
| taskGitUrl               | The url to the git repo where the release-service-catalog tasks to be used are stored     | No       | -             |
| taskGitRevision          | The revision in the taskGitUrl repo to be used                                            | No       | -             |

## Changes in 0.4.3
* Undo changes introduced in 0.4.2
  * Early failure prevents pasting of internal pipelineRun or taskRun

## Changes in 0.4.2
* Improve logging of `internal-request`
  * Previously we would just swallow the output and if it failed for any reason, the log wouldn't have anything useful

## Changes in 0.4.1
* Use a temp file for `internal-request` result instead of a fixed file in the workspace to reduce risk
  of interference with other tasks

## Changes in 0.4.0
* Update the release-service-utils image and enable the internalRequests
  to be created using git-ref pipeline instead of cluster pipeline.

## Changes in 0.3.0
* The task now writes pushed file names to a results json file in the workspace

## Changes in 0.2.2
* Increase the InternalRequest PipelineRun timeout to 24 hours in total

## Changes in 0.2.1
* Increase the InternalRequest PipelineRun timeout to 4 hours in total

## Changes in 0.2.0
* The task now supports pushing disk images to Developer Portal
