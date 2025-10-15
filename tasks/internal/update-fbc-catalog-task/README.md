# update-fbc-catalog-task

Tekton task to submit a IIB build request to add/update fbc-fragments to an index image

## Parameters

| Name                        | Description                                                                            | Optional | Default value |
|-----------------------------|----------------------------------------------------------------------------------------|----------|---------------|
| fbcFragments                | FBC fragments built by Konflux as JSON array (e.g. ["fragment1", "fragment2"])         | No       | -             |
| fromIndex                   | Index image (catalog of catalogs) the FBC fragment will be added to                    | No       | -             |
| buildTags                   | List of additional tags the internal index image copy should be tagged with            | No       | -             |
| addArches                   | List of arches the index image should be built for                                     | No       | -             |
| buildTimeoutSeconds         | Timeout seconds to receive the build state                                             | Yes      | 3600          |
| iibServiceAccountSecret     | Secret with IIB credentials to be used                                                 | No       | -             |
| publishingCredentials       | Secret containing the publishing credentials used to fetch the image config            | No       | -             |
| mustPublishIndexImage       | Whether the index image should be published (pre-determined by prepare-fbc-parameters) | Yes      | false         |
| mustOverwriteFromIndexImage | Whether to overwrite the from index image (pre-determined by prepare-fbc-parameters)   | Yes      | false         |
| caTrustConfigMapName        | The name of the ConfigMap to read CA bundle data from                                  | Yes      | trusted-ca    |
| caTrustConfigMapKey         | The name of the key in the ConfigMap that contains the CA bundle data                  | Yes      | ca-bundle.crt |
