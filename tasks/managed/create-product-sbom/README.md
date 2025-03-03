# create-product-sbom

Tekton task to create a product-level SBOM to be uploaded to Atlas from
releaseNotes content.

## Parameters

| Name         | Description                                                             | Optional | Default value |
| ------------ | ----------------------------------------------------------------------- | -------- | ------------- |
| dataJsonPath | Path to the JSON string of the merged data containing the release notes | No       | -             |

## Changes in 0.2.1
* Fixed component-product relationship in SBOM.

## Changes in 0.2.0
* Output directory path instead of a file path.

## Changes in 0.1.1
* The release-service-utils image was updated to include a fix when generating name of product level SBOM - it should be based on "{product name} {product version}"

