# rh-sign-image

Task to create sign containers in snapshot with cosign

## Parameters

| Name           | Description                                                               | Optional | Default value        |
|----------------|---------------------------------------------------------------------------|----------|----------------------|
| snapshotPath   | Path to the JSON string of the mapped Snapshot spec in the data workspace | Yes      | snapshot_spec.json   |
| dataPath       | Path to the JSON string of the merged data to use in the data workspace   | Yes      | data.json            |


Data file is expected to contain attribute sign.configMapName which is config map holding needed
for the signing. The config map should contain the following keys:
* SIG_KEY - key used for signing
* AWS_REGION - region of the awskms
* AWS_ACCESS_KEY - access key for awskms
* AWS_SECRET_ACCESS_KEY - secret access key for awskms
* REGISTRY_USER - username for the docker registry where signatures should be stored
* REGISTRY_PASSWORD - password for the docker registry where signatures should be stored
