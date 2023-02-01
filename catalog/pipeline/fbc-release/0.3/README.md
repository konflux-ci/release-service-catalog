# FBC Release Pipeline

FBC Release Pipeline

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| snapshot | The Snapshot in JSON format | No | - |
| enterpriseContractPolicy | JSON representation of the EnterpriseContractPolicy | No | - |
| fbcFragment | FBC fragment built by HACBS | No | - |
| fromIndex | Index image (catalog of catalogs) the FBC fragment will be added to | No | - |
| overWriteFromIndex | Boolean indicating if the fromIndex should be overwritten | Yes | - |
| binaryImage | OCP binary image to be baked into the index image | Yes | - |
| buildTags | List of additional tags the internal index image copy should be tagged with | Yes | - |
| addArches | List of arches the index image should be built for | Yes | - |

## Changes since 0.2

* Pipeline name was changed:
  * metadata.name = `fbc-release`
* Task dependency change
  * `create-internal-request` must run after `verify-enterprise-contract`
