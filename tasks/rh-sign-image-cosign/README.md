# rh-sign-image-cosign

Tekton task to sign container images in snapshot by cosign.

## Parameters

| Name                   | Description                                                                                                                                                                                                                                       | Optional | Default value |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------- |
| snapshotPath           | Path to the JSON string of the mapped Snapshot spec in the data workspace                                                                                                                                                                         | No       | -             |
| secretName             | Name of secret containing needed credentials                                                                                                                                                                                                      | No       | -             |
| signRegistryAccessPath | The relative path in the workspace to a text file that contains a list of repositories that needs registry.access.redhat.com image references to be signed (i.e. requires_terms=true), one repository string per line, e.g. "rhtas/cosign-rhel9". | No       | -             |

## Changes in 1.0.0
* Added mandatory parameter `signRegistryAccessPath`.
  * The relative path in the workspace to a text file that contains a list of repositories
    that needs registry.access.redhat.com image references to be signed (i.e.
    requires_terms=true), one repository string per line, e.g. "rhtas/cosign-rhel9".
  * Only components for which the repository is included in the file will get
    the registry.access.redhat.com references signed.
* `skopeo inspect` call is now done on the source image (`containerImage` in snapshot), rather
  than on the target location (`repository` in mapped snapshot). This puts it in line
  with what's done in `rh-sign-image`, but also, we might want to sign the images before
  they're actually pushed.

## Changes in 0.3.0
* Make rekor url configurable

## Changes in 0.2.0
* Identity passed to cosign uses tags mentioned in .tags in the Snapshot instead of digests
