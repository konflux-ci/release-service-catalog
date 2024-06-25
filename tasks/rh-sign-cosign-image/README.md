# rh-sign-cosign-image

Task to create sign containers in snapshot with cosign

## Parameters

| Name           | Description                                                               | Optional | Default value  |
|----------------|---------------------------------------------------------------------------|----------|----------------|
| snapshotPath   | Path to the JSON string of the mapped Snapshot spec in the data workspace | No       |                |
| dataPath       | Path to the JSON string of the merged data to use in the data workspace   | No       |                |
| secretName     | Name of the secret to use for signing                                     | No       |                |


Data file is expected to contain attribute sign.configMapName which is config map holding needed
for the signing. The config map should contain the following keys:
* SIG_KEY - key used for signing
