# FBC Release Pipeline

FBC Release Pipeline

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| snapshot | The Snapshot in JSON format | No | - |
| enterpriseContractPolicy | JSON representation of the EnterpriseContractPolicy | No | - |
| fromIndex | Index image (catalog of catalogs) the FBC fragment will be added to | No | - |
| overWriteFromIndex | Boolean indicating if the fromIndex should be overwritten | Yes | "false" |
| binaryImage | OCP binary image to be baked into the index image | Yes | "" |
| buildTags | List of additional tags the internal index image copy should be tagged with | Yes | "[]"|
| addArches | List of arches the index image should be built for | Yes | "[]" |
| requestUpdateTimeout | Max seconds to wait until the status is updated | Yes | - |
| buildTimeoutSeconds | Max seconds to wait until the build finishes | Yes | - |

## Changes since 0.5

Upgrade create-internal-request task to version 0.3
