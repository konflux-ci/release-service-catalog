# check-embargoed-cves-task

Checks if any passed CVEs are embargoed.
The task will always exit 0 even if something fails. This is because the task result will not be
set if the task fails, and the task result should always be set and propagated back to the cluster
that creates the internal request. The success/failure is handled in the task creating the internal
request.

## Parameters

| Name                 | Description                                                                                | Optional | Default value |
|----------------------|--------------------------------------------------------------------------------------------|----------|---------------|
| cves                 | String containing a space separated list of CVEs to check (e.g. 'CVE-123 CVE-234 CVE-345') | No       | -             |
| caTrustConfigMapName | The name of the ConfigMap to read CA bundle data from                                      | Yes      | trusted-ca    |
| caTrustConfigMapKey  | The name of the key in the ConfigMap that contains the CA bundle data                      | Yes      | ca-bundle.crt |
