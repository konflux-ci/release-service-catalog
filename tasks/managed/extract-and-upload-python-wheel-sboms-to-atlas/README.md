# extract-and-upload-python-wheel-sboms-to-atlas

Extract Fromager-generated SBOMs from Python wheels and upload them to
Atlas (TPA) using the Mobster CLI

## Parameters

| Name                    | Description                                                                                           | Optional | Default value        |
|-------------------------|-------------------------------------------------------------------------------------------------------|----------|----------------------|
| atlasApiUrl             | URL of the Atlas/TPA API server                                                                       | No       | -                    |
| ssoTokenUrl             | URL of the SSO token issuer for TPA authentication                                                    | No       | -                    |
| atlasSecretName         | Name of the K8s secret containing TPA SSO credentials (keys sso_account, sso_token)                   | No       | -                    |
| sourceDataArtifact      | Trusted Artifact containing the extracted wheels and release data                                     | No       | -                    |
| dataDir                 | The location where data will be stored                                                                | Yes      | /var/workdir/content |
| filesDir                | The relative path within dataDir where wheel files are located                                        | Yes      | files                |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored | No       | -                    |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                        | No       | -                    |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                             | No       | -                    |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created                                                     | Yes      | 1d                   |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                       | Yes      | ""                   |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                | Yes      | ""                   |
