# check-file-updates-task

Internal task to check whether Konflux `fileUpdates` changes are already complete for a
given componentGroup and GitLab repository.

This task is intentionally "best effort": on errors (missing credentials, API errors, invalid data),
it returns file_updates_complete=false and result=Failure instead of failing the TaskRun. This enables
managed pipelines to treat the check as incomplete and continue safely.

## Parameters

| Name                           | Description                                                               | Optional | Default value       |
|--------------------------------|---------------------------------------------------------------------------|----------|---------------------|
| upstream_repo                  | Git repository (GitLab) where fileUpdates merge requests are created      | No       | -                   |
| componentGroup                 | Component group being released (used to identify Konflux fileUpdates MRs) | No       | -                   |
| file_updates_secret            | Secret containing GitLab host/access token used by internal services      | Yes      | file-updates-secret |
| apiRetryCount                  | Number of retries for GitLab API calls                                    | Yes      | 3                   |
| apiConnectTimeout              | Connection timeout in seconds for GitLab API calls                        | Yes      | 10                  |
| apiMaxTime                     | Maximum time in seconds for GitLab API calls                              | Yes      | 30                  |
| caTrustConfigMapName           | The name of the ConfigMap to read CA bundle data from                     | Yes      | trusted-ca          |
| caTrustConfigMapKey            | The name of the key in the ConfigMap that contains the CA bundle data     | Yes      | ca-bundle.crt       |
| internalRequestPipelineRunName | Name of the PipelineRun that called this task                             | No       | -                   |
