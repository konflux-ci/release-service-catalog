# update-infra-deployments

* This task clones a GitHub repository specified in the 'targetGHRepo' key of the input data file.
* If 'targetGHRepo' is not provided, it defaults to 'defaultTargetGHRepo: redhat-appstudio/infra-deployments'.
* It then runs a script obtained from the 'infra-deployment-update-script' key in the data file,
  which can modify text files.
* Finally, it generates a pull request for the specified repository using the modified files.

## Parameters

| Name                           | Description                                                                                                                | Optional | Default value                      |
|--------------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|------------------------------------|
| dataJsonPath                   | path to data json file                                                                                                     | No       | -                                  |
| snapshotPath                   | path to snapshot json file                                                                                                 | No       | -                                  |
| defaultTargetGHRepo            | GitHub repository of the infra-deployments code                                                                            | Yes      | redhat-appstudio/infra-deployments |
| defaultGithubAppID             | Default ID of Github app used for updating PR                                                                              | Yes      | 305606                             |
| defaultGithubAppInstallationID | Default Installation ID of Github app in the organization                                                                  | Yes      | 35269675                           |
| sharedSecret                   | secret in the namespace which contains private key for the GitHub App                                                      | Yes      | infra-deployments-pr-creator       |
| ociStorage                     | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                              |
| ociArtifactExpiresAfter        | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                                 |
| trustedArtifactsDebug          | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                                 |
| orasOptions                    | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                                 |
| sourceDataArtifact             | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                                 |
| dataDir                        | The location where data will be stored                                                                                     | Yes      | /var/workdir/release               |
| taskGitUrl                     | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                                  |
| taskGitRevision                | The revision in the taskGitUrl repo to be used                                                                             | No       | -                                  |
| caTrustConfigMapName           | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca                         |
| caTrustConfigMapKey            | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt                      |
