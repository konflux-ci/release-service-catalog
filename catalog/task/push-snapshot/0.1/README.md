# push-application-snapshot

Tekton task to push snapshot images to an image registry using `skopeo copy`.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| mappedApplicationSnapshot | JSON string representing the ApplicationSnapshot | No | - |
| retries | Retry copy N times | Yes | 0 |
