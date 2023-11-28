# add-fbc-contribution

Task to create a internalrequest to add fbc contributions to index images

## Parameters

| Name           | Description                                                               | Optional | Default value        |
|----------------|---------------------------------------------------------------------------|----------|----------------------|
| snapshotPath   | Path to the JSON string of the mapped Snapshot spec in the data workspace | Yes      | snapshot_spec.json   |
| dataPath       | Path to the JSON string of the merged data to use in the data workspace   | Yes      | data.json            |
| requestTimeout | InternalRequest timeout                                                   | Yes      | 180                  |
| binaryImage    | binaryImage value updated by update-ocp-tag task                          | No       |                      |
| fromIndex      | fromIndex value updated by update-ocp-tag task                            | No       |                      |

## changes in 1.4.0
- add the possibility of setting a stagedIndex tag
 
## changes in 1.3.0
- add the possibility of setting a hotfix tag
- replace the `fbcOptIn` result with `mustSignIndexImage` and `mustPublishIndexImage`
  to control the pipeline flow

## changes in 1.2.0
- Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## changes in 1.1.0
- add `requestTargetIndex` result
