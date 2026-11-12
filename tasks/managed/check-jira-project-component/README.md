# check-jira-project-component

Tekton task to validate that the security-tracker labels of every container image in the snapshot refer to a
valid Jira project and component.

For each image component the task reads the `com.redhat.security-tracker-project` label (via `skopeo inspect`),
which holds a Jira project key (e.g. `OCPBUGS`). The Jira server is fixed (redhat.atlassian.net), so the label
carries only the project key rather than a full URL. The task confirms the project exists in Jira, then resolves
a Jira component using a fallback chain: `name`, `com.redhat.component`, and finally
`com.redhat.security-tracker-component`. The first label whose value matches a component of the Jira project
wins. Images without a `com.redhat.security-tracker-project` label are skipped (label presence is enforced
separately by the release policy).

With `enforce` set to true (the default), any validation failure (missing project, or no label value matching a
component of the project) causes the task to fail. With `enforce` set to false, failures are logged as warnings
and the task completes successfully. A failure to reach or authenticate to Jira always fails the task, regardless
of the `enforce` setting.

## Parameters

| Name                    | Description                                                                                                                                                                                                                                                                                               | Optional | Default value                |
|-------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|------------------------------|
| snapshotPath            | Path to the JSON string of the mapped Snapshot spec in the data workspace                                                                                                                                                                                                                                 | No       | -                            |
| jiraSecret              | The kubernetes secret used to authenticate to Jira. It must contain two keys: 'email' and 'token' for Jira basic authentication.                                                                                                                                                                          | Yes      | konflux-advisory-jira-secret |
| enforce                 | If set to true (the default), validation failures will be logged as errors, causing the task to fail. If set to false, validation failures will be logged as warnings instead, allowing the task to complete successfully. A failure to connect to Jira always fails the task regardless of this setting. | Yes      | true                         |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                                                                                                                                                                                                 | Yes      | empty                        |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire                                                                                                                                                                                | Yes      | 1d                           |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                                                                                                                                                                                                    | Yes      | ""                           |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                                                                                                                                                                                                           | Yes      | ""                           |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                                                                                                                                                                                                       | Yes      | ""                           |
| dataDir                 | The location where data will be stored                                                                                                                                                                                                                                                                    | Yes      | /var/workdir/release         |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                                                                                                                                                                                                     | No       | -                            |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                                                                                                                                                                                                            | No       | -                            |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                                                                                                                                                                                                     | Yes      | trusted-ca                   |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                                                                                                                                                                                                     | Yes      | ca-bundle.crt                |
