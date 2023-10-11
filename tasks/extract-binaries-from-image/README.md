# extract-binaries-from-image

Tekton task that extracts binaries to be released on github.com from an image.

The path to the directory inside the provided workspace where the binaries were
saved is provided as a result.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| image_binaries_path | Path inside the image where the binaries to extract are stored | Yes | /releases |
| snapshotPath | Path to the JSON string of the mapped Snapshot spec in the data workspace | Yes | snapshot.json |
| subdirectory | Subdirectory inside the workspace to be used for storing the binaries | Yes | "" |
