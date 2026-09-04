# create-github-release

Tekton task that creates a release in GitHub.com via the API.

It extracts binary files from the container image and uploads them along with
SHA256SUMS and signature files (from the TA chain) to the GitHub release.

Binary uploads accept any combination of *.zip, *.tar.gz, and *.json from the
image. SHA256SUMS and .sig files from the trusted-artifact chain are required.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value        |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| repository              | The github repository where the release should be created                                                                  | No       | -                    |
| release_version         | The version string of the new release                                                                                      | No       | -                    |
| githubSecret            | The kube secret to use to authenticate to GitHub, containing one key: token                                                | No       | -                    |
| content_directory       | The directory inside the workspace to find SHA256SUMS and signature files                                                  | No       | -                    |
| snapshotPath            | Path to the JSON string of the mapped Snapshot spec in the data workspace                                                  | No       | -                    |
| imageBinariesPath       | Path inside the image where the binaries to extract are stored                                                             | Yes      | releases             |
| resultsDirPath          | Path to the results directory in the data workspace                                                                        | No       | -                    |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                   |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                   |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                   |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                   |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                    |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | -                    |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca           |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt        |
