# rh-sign-image

Task to create internalrequests to sign snapshot components

## Parameters

| Name           | Description                                                               | Optional | Default value        |
|----------------|---------------------------------------------------------------------------|----------|----------------------|
| snapshotPath   | Path to the JSON string of the mapped Snapshot spec in the data workspace | Yes      | snapshot_spec.json   |
| dataPath       | Path to the JSON string of the merged data to use in the data workspace   | Yes      | data.json            |
| requester      | Name of the user that requested the signing, for auditing purpose         | No       |                      |
| commonTags      | Space separated list of common tags to be used when publishing           | No       |                      |
| requestTimeout | InternalRequest timeout                                                   | Yes      | 180                  |

## Changes since 1.0.0
* Translate docker-reference when signing images
  - Before this change, signing request would be sent with the actual quay location of the image. Instead, the reference
    need to be translated to the public facing reference.
    - E.g. quay.io/redhat-prod/rhtas-tech-preview----tuf-server-rhel9:1.0.beta needs to be translated to
      registry.redhat.io/rhtas-tech-preview/tuf-server-rhel9:1.0.beta. Similarly, quay.io/redhat-pending references
      need to be translated to registry.stage.redhat.io.

## Changes since 0.1.0
* Also sign floating tag
  - In addition to pushing $tagPrefix-$timestamp tag, we now also push
    $tagPrefix tag a.k.a. commonTag, so this needs to be signed as well
  - Rename parameter commonTag to commonTags which will contain both tags to sign
