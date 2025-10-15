# get-advisory-severity

This task gets the advisory severity. It does this by querying OSIDB for each CVE present in the
releaseNotesImages. For each CVE, the overall impact it is looked at. If the OSIDB entry lists an
impact for the specific affected component, that is used instead of the overall impact. The highest
impact from all of the CVEs is returned as a task result.

## Parameters

| Name                           | Description                                                                    | Optional | Default value |
|--------------------------------|--------------------------------------------------------------------------------|----------|---------------|
| releaseNotesImages             | Base64 string of gzipped JSON array of image specific details for the advisory | No       | -             |
| internalRequestPipelineRunName | name of the PipelineRun that called this task                                  | No       | -             |
| caTrustConfigMapName           | The name of the ConfigMap to read CA bundle data from                          | Yes      | trusted-ca    |
| caTrustConfigMapKey            | The name of the key in the ConfigMap that contains the CA bundle data          | Yes      | ca-bundle.crt |
