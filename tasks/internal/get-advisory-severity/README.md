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
