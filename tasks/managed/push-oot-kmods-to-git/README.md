# push-oot-kmods-to-git

Task to upload out-of-tree kernel modules and optionally RPMs to a private vendor git repo

## Parameters

| Name                  | Description                                                                            | Optional | Default value                                             |
|-----------------------|----------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| signedKmodsPath       | Path where the kernel modules are stored relative to the dataDir                       | No       | -                                                         |
| rpmPath               | Path where the RPM packages are stored relative to the dataDir (optional)              | Yes      | ""                                                        |
| dataDir               | The absolute path to the working directory                                             | Yes      | /var/workdir/release                                      |
| gitRepoUrl            | Repository URL where the artifacts will be pushed                                      | No       | -                                                         |
| gitBranch             | Specific branch in the repository                                                      | No       | -                                                         |
| gitTokenSecret        | The name of the Kubernetes secret containing the Git token                             | No       | -                                                         |
| sourceDataArtifact    | OCI reference to the trusted artifact containing the dataDir contents                  | No       | -                                                         |
| orasOptions           | oras options to pass to Trusted Artifacts calls                                        | Yes      | ""                                                        |
| trustedArtifactsDebug | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable | Yes      | ""                                                        |
| taskGitUrl            | The git repository URL for StepAction resolution                                       | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision       | The git revision for StepAction resolution                                             | Yes      | main                                                      |
