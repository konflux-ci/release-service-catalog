# push-oot-kmods-to-azure

Task to upload out-of-tree kernel modules to Azure Blob Storage

## Parameters

| Name                  | Description                                                                            | Optional | Default value                                             |
|-----------------------|----------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| signedKmodsPath       | Path where the kernel modules are stored relative to the dataDir                       | No       | -                                                         |
| dataDir               | The absolute path to the working directory                                             | Yes      | /var/workdir/release                                      |
| azureStorageAccount   | Azure Storage account name                                                             | No       | -                                                         |
| azureContainer        | Azure Blob container name                                                              | No       | -                                                         |
| azureSpSecret         | Kubernetes Secret with AZURE_TENANT_ID, AZURE_CLIENT_ID, and AZURE_CLIENT_SECRET       | No       | -                                                         |
| sourceDataArtifact    | Location of trusted artifacts to be used to populate data directory                    | Yes      | ""                                                        |
| orasOptions           | oras options to pass to Trusted Artifacts calls                                        | Yes      | ""                                                        |
| trustedArtifactsDebug | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable | Yes      | ""                                                        |
| taskGitUrl            | The git repository URL for task and StepAction resolution                              | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision       | The git revision for task and StepAction resolution                                    | Yes      | main                                                      |
