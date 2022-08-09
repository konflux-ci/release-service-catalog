# Milestone-5 Release Pipeline

Tekton pipeline to release HACBS Application Snapshot.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| applicationSnapshot | The ApplicationSnapshot in JSON format | No | - |
| policy | Name of the policy to apply when validating the enterprise contract | No | - |
| extraConfigGitUrl |URL to the remote Git repository containing the extra config | No | - |
| extraConfigGitRevision | Revision to fetch from the remote Git repository containing the extra config | No | - |
| extraConfigPath | Path to the extra config file within the repository | No | - |
| postCleanUp | Cleans up workspace after finishing executing the pipeline | Yes | true |
