# Maintenance

## Rotating the Github secret

Some suites use dedicated bot accounts instead of the shared token:
  * `rhtap-service-push` uses `rhtap-service-push-e2e-bot` (vault: `stonesoup/staging/release/e2e/rhtap-service-push-e2e-bot`)
  * `fbc-release` uses `fbc-release-e2e-bot` (vault: `stonesoup/staging/release/e2e/fbc-release-e2e-bot`)
  * All other suites use the shared token (vault: `stonesoup/staging/release/e2e/e2e-base-github-token`)

All tokens (shared and per-suite) require these classic PAT scopes:
  * repo
  * admin:repo_hook
  * delete_repo

### Rotating a token (shared or per-suite)

  * Regenerate the token from GitHub with the scopes listed above
  * Decrypt the tenant vault for each suite that uses the token
```shell
ansible-vault decrypt vault/tenant-secrets.yaml --output "resources/tenant/secrets/tenant-secrets.yaml" --vault-password-file /tmp/vaultpass
```
  * update resources/tenant/secrets/tenant-secrets.yaml
    * update password for secret pipelines-as-code-secret-*
  * encrypt each one
```shell
ansible-vault encrypt resources/tenant/secrets/tenant-secrets.yaml --output "vault/tenant-secrets.yaml" --vault-password-file /tmp/vaultpass
```
  * commit and create PR
  * update the corresponding vault secret
  * force refresh the corresponding ExternalSecret on stg-rh01
```shell
# shared token
kubectl annotate es e2e-test-github-token force-sync=$(date +%s) --overwrite -n konflux-release-service-tenant
# per-suite tokens
kubectl annotate es rhtap-service-push-e2e-github-token force-sync=$(date +%s) --overwrite -n konflux-release-service-tenant
kubectl annotate es fbc-release-e2e-github-token force-sync=$(date +%s) --overwrite -n konflux-release-service-tenant
```
  * Remove any old pipelines-as-code-secret- secrets
```
kubectl get secrets --no-headers | grep pipelines-as-code-secret- | awk '{print "kubectl delete secret/"$1}'
```
  * Failure to the above step may result in these errors:
```
{"pac":{"state":"error","error-id":74,"error-message":"74: Access token is unrecognizable by GitHub"},"message":"done"}
```
## Should you require to add or update a secret, follow these steps:
```shell
ansible-vault decrypt vault/tenant-secrets.yaml --output "/tmp/tenant-secrets.yaml" --vault-password-file <vault password file>
```

```shell
vi /tmp/tenant-secrets.yaml
```

```shell
ansible-vault encrypt /tmp/tenant-secrets.yaml --output "vault/tenant-secrets.yaml" --vault-password-file <vault password file>
```

```shell
rm /tmp/tenant-secrets.yaml
```
