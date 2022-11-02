# add-bundles-to-image-index

Calls IIB service to submit a build request to add operator bundles to an index image

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| IIB_URL | IIB Service URL | No | - |
| IIB_JSON_BUILD_ARGS | IIB request arguments in JSON format - See below | No | 0 |
| IIB_SECRET | Secret name that contains IIB credentials and Registry - See below the *Secret* information | No | 0 |
| IIB_BUILD_TIMEOUT_SECONDS | Timeout seconds when waiting for the build to finish | No | Tekton default task timeout |

#### IIB_JSON_BUILD_ARGS

Sample JSON request including the `{TOKEN}` to be replaced with the `registry_secret` item from the `IIB_SECRET`.

```
{
  "binary_image": "quay.io/operator-framework/upstream-registry-builder:v1.5.9",
  "bundles": [
    "quay.io/user/openshift-bundle-example-container:v1"
  ],
  "from_index": "quay.io/iib-stage/iib:4",
  "overwrite_from_index": true,
  "overwrite_from_index_token": "{TOKEN}",
  "distribution_scope": "state",
}
```

### Secret

The secret should contain the following key/pair items, required by the task.

| Name | Description | Optional |
|------|-------------|----------|
| krb5_username | Kerberos 5 username to authenticate | no |
| krb5_password  | Kerberos 5 password to authenticate | no |
| krb5.conf | Content of the krb5.conf file | no |
| registry_secret | Registry credentials to pull/push the image or bundle. Requires the use of `{TOKEN}` placeholder in the `overwrite_from_index_token` of the `IIB_JSON_BUILD_ARGS` . | yes |

```
oc create secret generic <IIB_SECRET> --from-literal='krb5_username=foo' --from-literal='krb5_password=bar' \
   --from-literal='registry_secret=foo:bar' --from-file=path/to/krb5.conf
```
