# embargo-check

Tekton task to check if any issues or CVEs in the releaseNotes key of the data.json are embargoed. It checks the issues
by server using curl and checks the CVEs via an InternalRequest. If any issue does not exist or any CVE is embargoed,
the task will fail. The task will also fail if a Jira issue listed is for a component that does not exist in the
releaseNotes.content.images section or if said component does not list the CVE from the issue.

## Parameters

| Name                     | Description                                                                               | Optional | Default value |
|--------------------------|-------------------------------------------------------------------------------------------|----------|---------------|
| dataPath                 | Path to data JSON in the data workspace                                                   | No       | -             |
| requestTimeout           | InternalRequest timeout                                                                   | Yes      | 180           |
| pipelineRunUid           | The uid of the current pipelineRun. Used as a label value when creating internal requests | No       | -             |
| taskGitUrl               | The url to the git repo where the release-service-catalog tasks to be used are stored     | No       | -             |
| taskGitRevision          | The revision in the taskGitUrl repo to be used                                            | No       | -             |

## Changes in 1.0.0
* Authentication is added to checking issues in issues.redhat.com
* If the issue exists and is not of type `Vulnerability`, the task will pass on that issue
* If the issue is of type `Vulnerability`
  * If the `Downstream Component Name` from the issue is not listed in the `releaseNotes.content.images`
    section, the task will fail
  * If the `CVE ID` from the issue is not present in its component's fixed cves section, the task will fail

## Changes in 0.5.0
* Added taskGiturl and taskGitRevision parameters to be passed to the internalRequest
* The pipeline is called via git resolver now instead of cluster resolver
  * This was done by changing from `-r` to `--pipeline` in the `internal-request` call
  * The base image was updated to include this new functionality
* Updated logic to determine InternalRequest name more reliably

## Changes in 0.4.1
* fix linting issues in embargo-check task 

## Changes in 0.4.0
* updated the base image used in this task

## Changes in 0.3.0
* updated the base image used in this task

## Changes in 0.2.0
* remove `dataPath` default value
