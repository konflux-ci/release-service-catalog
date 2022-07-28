# push-application-snapshot

Tekton task that pushes container images to a registry using `skopeo copy`.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| srcImageURL | Source Image URL | No | - |
| destImageURL | Destination Image URL | No | 0 |
| srcToken | Source auth token | No | - |
| destToken | Destination auth token | No | - |
| retries | JSON string representing the ApplicationSnapshot | Yes | 0 |
