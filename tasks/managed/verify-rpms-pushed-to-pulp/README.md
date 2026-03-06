# verify-rpms-pushed-to-pulp

Verifies that RPMs recorded in push-rpms-to-pulp results are present in the
Pulp repositories with matching digests. Runs after push-rpms-to-pulp in the
pipeline to confirm the push succeeded.

## Parameters

| Name               | Description                                                                 | Optional | Default value |
|--------------------|-----------------------------------------------------------------------------|----------|---------------|
| dataDir            | The workspace root where the push task wrote results                        | No       | -             |
| resultsDirPath     | Path segment under dataDir containing push-rpms-to-pulp-results.json        | No       | -             |
| sourceDataArtifact | Trusted artifact from push-rpms-to-pulp (path=dataDir) to read results from | No       | -             |
| PULP_DOMAIN        | The Pulp domain used by the push task                                       | No       | -             |
| PULP_SECRET_NAME   | The name of the secret containing the Pulp cli.toml file                    | No       | -             |
| taskGitUrl         | Git URL for the catalog (for use-trusted-artifact stepaction)               | No       | -             |
| taskGitRevision    | Git revision for the catalog                                                | No       | -             |
