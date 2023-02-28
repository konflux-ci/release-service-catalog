# Push to External Registry Pipeline

Tekton pipeline to push images to an external registry.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| snapshot | The Snapshot in JSON format | No | - |
| enterpriseContractPolicy | JSON representation of the policy to be applied when validating the enterprise contract | No | - |
| extraConfigGitUrl |URL to the remote Git repository containing the extra config | No | - |
| extraConfigGitRevision | Revision to fetch from the remote Git repository containing the extra config | No | - |
| extraConfigPath | Path to the extra config file within the repository | No | - |
| tag | The default tag to use when mapping file does not contain a tag | No | - |
| addShaTag | When pushing the snapshot components, also push a tag with the image sha | Yes | true |
| addTimestampTag | When pushing the snapshot components, also push a tag with the current timestamp | Yes | false |
| pyxisServerType | The Pyxis server type to use. Options are 'production' and 'stage' | No | - |
| pyxisSecret | The kubernetes secret to use to authenticate to Pyxis | No | - |
| postCleanUp | Cleans up workspace after finishing executing the pipeline | Yes | true |

## Changes since 0.3

* Upgrade push-snapshot task to version 0.5
  * addShaTag parameter is now supported and passed as a pipeline parameter to the task
  * addTimestampTag parameter is now supported and passed as a pipeline parameter to the task

## Changes since 0.2

* push-snapshot now supports tag parameter

## Changes since 0.1

* Upgrade create-pyxis-image task to version 0.2
  * correct incorrect snapshot param

