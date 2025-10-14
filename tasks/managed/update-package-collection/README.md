# update-package-collection Task

The update-package-collection Task is a Tekton Task to update package collections for a given application. It can create InternalRequests for adding or deleting builds (NVRs) in a package collection based on snapshot and data JSON files, and integrates with OCI and Trusted Artifacts.

This Task ensures traceability by writing results back even if errors occur.

## Parameters

| Name                    | Description                                                                          | Optional | Default                       |
| ----------------------- | ------------------------------------------------------------------------------------ | -------- | ----------------------------- |
| snapshotPath            | Path to the JSON file of the mapped Snapshot spec in the data workspace              | No       | –                             |
| dataPath                | Path to the JSON file of the merged data to use in the data workspace                | No       | –                             |
| ociStorage              | OCI repository where Trusted Artifacts are stored                                    | Yes      | `"empty"`                     |
| sourceDataArtifact      | Location of trusted artifacts used to populate the data directory                    | Yes      | `""`                          |
| ociArtifactExpiresAfter | Expiration date for OCI artifacts. Empty string = artifacts do not expire            | Yes      | `"1d"`                        |
| trustedArtifactsDebug   | Flag to enable debug logging for trusted artifacts. Non-empty string enables debug   | Yes      | `""`                          |
| orasOptions             | ORAS options to pass to Trusted Artifacts calls                                      | Yes      | `""`                          |
| dataDir                 | Location where data will be stored                                                   | Yes      | `/var/workdir/release`        |
| taskGitUrl              | Git repository URL containing the Tekton task YAMLs and step actions                 | No       | –                             |
| taskGitRevision         | Revision in `taskGitUrl` to use                                                      | No       | –                             |
| action                  | Action type of package collection (`add-builds` or `delete-builds`)                  | No       | –                             |
| env                     | Target environment (`dev`, `stage`, `prod`)                                          | Yes      | `"prod"`                      |
| request                 | Type of InternalRequest to create                                                    | Yes      | `"update-package-collection"` |
| synchronously           | Whether the Task should wait for InternalRequests to complete                        | Yes      | –                             |
| pipelineRunUid          | UID of the current PipelineRun. Used as a label value when creating InternalRequests | No       | –                             |
