# get-advisory-severity

This task gets the advisory severity. It does this by querying OSIDB for each CVE present in the
releaseNotesImages. For each CVE, the overall impact it is looked at. If the OSIDB entry lists an
impact for the specific affected component, that is used instead of the overall impact. The highest
impact from all of the CVEs is returned as a task result.


## Parameters

| Name                           | Description                                           | Optional | Default value |
|--------------------------------|-------------------------------------------------------|----------|---------------|
| releaseNotesImages             | Json array of image specific details for the advisory | No       | -             |
| internalRequestPipelineRunName | Name of the PipelineRun that called this task         | No       | -             |

## Changes in 0.2.1
* Improve logging by enabling `set -x`

## Changes in 0.2.0
* Instead of comparing `ps_component` with the component name to check for component specific severity, use the
  `repository` value from the component in the snapshot and compare that with the `repository_url` from the `purl`
  in OSIDB

## Changes in 0.1.1
* Fix bug regarding the jq query that determines the number of images
