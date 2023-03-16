# create-internal-request

Creates an InternalRequest resource to call IIB service

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| pipelineRunName | The name of the Parent PipelineRun for this task | No | `ir-$(context.pipelineRun.name)` |
| binaryImage | OCP `binaryImage` to be baked into the `fromIndex` image | Yes | |
| fbcFragment | `fbcFragment` built by HACBS | No | |
| fromIndex | `fromIndex` image (catalog of catalogs) the fbcFragment will be added to | Yes | |
| overwriteFromIndex | Boolean indicating if the `fromIndex` should be overwritten | Yes | |
| buildTags | List of additional `buildTags` the internal `fromIndex` image copy should be tagged with | Yes | |
| buildArches | List of `buildArches` the `fromIndex` should be built for | Yes | |
| requestUpdateTimeout | List of `buildArches` the `fromIndex` should be built for | Yes | 360|
| buildTimeoutSeconds | List of `buildArches` the `fromIndex` should be built for | Yes | 300|


## Changelog

### changes since 0.1
- adds `resolvedIndexImage` result
- adds params `requestUpdateTimeout` and `buildTimeoutSeconds`
