# extract-py-artifacts

Extract Python packages from OCI artifacts for signing and upload.
The populate-release-notes step parses wheel SBOMs for pkg:pypi PURLs,
populates releaseNotes.content.artifacts, and ensures mapping.components
entries have contentType set to "generic" for downstream advisory creation.
The fetch-chains-provenance step verifies and retrieves Tekton Chains SLSA provenance
using cosign with the public key from k8s://openshift-pipelines/public-key.
The pipeline service account must have get access to this secret

## Parameters

| Name                    | Description                                                                                           | Optional | Default value |
|-------------------------|-------------------------------------------------------------------------------------------------------|----------|---------------|
| SNAPSHOT_PATH           | Path to the snapshot spec file containing image information                                           | No       | -             |
| sourceDataArtifact      | Trusted Artifact to use to obtain the Snapshot                                                        | No       | -             |
| dataDir                 | The location where data will be stored                                                                | Yes      | /var/workdir  |
| filesDir                | The relative path within dataDir where files will be extracted                                        | Yes      | files         |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                             | No       | -             |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created                                                     | Yes      | 1d            |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                       | Yes      | ""            |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                | Yes      | ""            |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored | No       | -             |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                        | No       | -             |
| dataPath                | Path to data.json relative to dataDir                                                                 | No       | -             |
