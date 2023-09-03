# update-ocp-tag

Tekton task to update version tag of FBC pull-spec
 `fromIndex`, `targetIndex` and `binaryImage` with the 
 provided OCP version.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| fromIndex | The source Index image (catalog of catalogs) FBC fragment | No | - |
| targetIndex | Index image (catalog of catalogs) the FBC fragment will be added to | No | - |
| binaryImage | OCP binary image to be baked into the index image | No | - |
| ocpVersion |  OCP version fetched from fbcFragment | No | - |