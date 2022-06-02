# push-application-snapshot
This [Tekton Task](https://tekton.dev/docs/pipelines/tasks/#overview) is responsible for pushing the components defined by the [applicationSnapshot](#applicationSnapshot) from one registry to another.

## Parameters:

| Name | Description | Type | Optional | Default value |
|------|-------------|------|----------|---------------|
| applicationSnapshot | JSON string representation of the Application snapshot. See bellow for an example. | string | true | - |
| retries | Retry failed push N times before failing. May improve resilience over potentially unreliable networks. Maps to `skopeo copy --retry-times`***`N`*** ([upstream documentation](https://github.com/containers/skopeo/blob/main/docs/skopeo-copy.1.md#options))  | string | true | "0" |

---

### applicationSnapshot
The following code snippet conforms to the applicationSnapshot spec.
```
{
  "application": "foo",
  "images": [
    {
      "component": "component_fizz_1",
      "pullspec": "quay.io/src_namespace/src_repo_name@sha256:digest",
      "repository": "quay.io/dest_namespace/dest_repo_name"
    },
    {
      "component": "component_bang_3",
      "pullspec": "quay.io/src_namespace/src_repo_name",
      "repository": "quay.io/dest_namespace/dest_repo_name",
      "tag": "moocow_v1"
    }
  ]
}
```
| Key | Value | type |
|------|-------------|------|
| application | The name of the application | string |
| images | List of image mappings | array |
| *image* | Image mapping | object |
| compoent | Name of the component | string |
| pullspec | Image registry to pull the component image | string |
| repository | Image registry to push the component image | string |
| tag | string to tag images image at `repository` | string |

## Remarks:
* The `pullspec` digest (e.g. @sha256:...) may be ommitted.
* * If the `pullspec` digest is ommitted, then the digest is taken from ":latest" tag.
* The `repository` string value shall not contain any digest or tag strings.
* * Tags must be specified by the `tag` in json.
* * The digest is always computed from the `pullspec`.
* If the image digest already exists at destination `repository`, the push will be skipped.
* * A message will be printed for any skipped push.
* * Likewise, all successfully pushed images will be printed accordingly.
* Authentication is handled by Tekton.
* * The "authfile" is expected to exist in the workspace.
