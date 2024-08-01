# rh-sign-image-cosign

Tekton task to sign container images in snapshot by cosign.

## Parameters

| Name           | Description                                                               | Optional | Default value |
|----------------|---------------------------------------------------------------------------|----------|---------------|
| snapshotPath   | Path to the JSON string of the mapped Snapshot spec in the data workspace | No       | -             |
| secretName     | Name of secret containing needed credentials                              | No       | -             |

# Changelog

## Changes in 0.2.0

* Identity passed to cosign uses tags mentioned in .tags in the Snapshot instead of digests
