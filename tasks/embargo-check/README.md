# embargo-check

Tekton task to check if any issues or CVEs in the releaseNotes key of the data.json are embargoed. It checks the issues
by server using curl and checks the CVEs via an InternalRequest. If any issue or CVE is embargoed, the task will fail.

## Parameters

| Name                     | Description                                                                               | Optional | Default value |
|--------------------------|-------------------------------------------------------------------------------------------|----------|---------------|
| dataPath                 | Path to data JSON in the data workspace                                                   | No       | -             |
| requestTimeout           | InternalRequest timeout                                                                   | Yes      | 180           |
| pipelineRunUid           | The uid of the current pipelineRun. Used as a label value when creating internal requests | No       | -             |

## Changes in 0.4.0
* updated the base image used in this task

## Changes in 0.3.0
* updated the base image used in this task

## Changes in 0.2.0
* remove `dataPath` default value
