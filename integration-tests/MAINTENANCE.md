# Maintenance

## Rotating the Github secret
  * regenerate token from GH with scopes:
    * repo
    * admin:repo_hook
    * delete_repo
  * decrypt each tenant vault for each suite
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
  * update vault at _stonesoup/staging/release/e2e/e2e-base-github-token_
  * force refresh on rh01 prod
```shell
kubectl annotate es e2e-test-github-token force-sync=$(date +%s) --overwrite -n rhtap-release-2-tenant
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
