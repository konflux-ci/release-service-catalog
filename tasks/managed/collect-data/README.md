# collect-data

Tekton task to collect the information added to the data field of the release resources.

The purpose of this task is to collect all the data and supply it to the other task in the pipeline by creating
a json file called `data.json` in the workspace.

This task also stores the passed resources as json files in a workspace.

The parameters to this task are lowercase instead of camelCase because they are passed from the operator, and the
operator passes them as lowercase.

A task result is returned for each resource with the relative path to the stored JSON for it in the workspace.

Finally, the task checks that the keys from the correct resource (a key that should come from the ReleasePlanAdmission
should not be present in the Release data section).

## Parameters

| Name                    | Description                                                                                                                | Optional  | Default value                                             |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|-----------|-----------------------------------------------------------|
| release                 | Namespaced name of the Release                                                                                             | No        | -                                                         |
| releasePlan             | Namespaced name of the ReleasePlan                                                                                         | No        | -                                                         |
| releasePlanAdmission    | Namespaced name of the ReleasePlanAdmission                                                                                | No        | -                                                         |
| releaseServiceConfig    | Namespaced name of the ReleaseServiceConfig                                                                                | No        | -                                                         |
| snapshot                | Namespaced name of the Snapshot                                                                                            | No        | -                                                         |
| subdirectory            | Subdirectory inside the workspace to be used                                                                               | Yes       | ""                                                        |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes       | empty                                                     |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes       | 1d                                                        |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes       | ""                                                        |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes       | ""                                                        |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes       | ""                                                        |
| dataDir                 | The location where data will be stored                                                                                     | Yes       | $(workspaces.data.path)                                   |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | Yes       | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | Yes       | production                                                |
