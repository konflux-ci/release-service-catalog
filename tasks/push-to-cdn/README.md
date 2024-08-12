# push-to-cdn

Tekton task to push content to Red Hat's CDN 

 * This task uses [exodus-rsync](https://github.com/release-engineering/exodus-rsync) to push content to Red Hat's CDN.
## Parameters

| Name         | Description                                                          | Optional | Default value |
|--------------|----------------------------------------------------------------------|----------|---------------|
| exodusGwUrl  | URL of the Exodus Gateway                                            | No       | -             |
| exodusGwEnv  | Environment to use in the Exodus GatewayGateway                      | No       | -             |
| exodusGwCert | Secret containing the Exodus Gateway certificate                     | No       | -             |
| exodusGwKey  | Secret containing the Exodus Gateway key                             | No       | -             |
| binariesDir  | The directory inside the workspace where the binaries are stored     | Yes      | "binaries"    |
| subdirectory | Subdirectory inside the workspace to be used for storing the results | Yes      | ""            |

## Changes in 0.2.1
* remove src (-s) and dest (-d) options for rsync

## Changes in 0.2.0
* Updated the base image used in this task
