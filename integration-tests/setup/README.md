# e2e setup for Konflux RH01 Staging
## Service Account
* A `ServiceAccount` is needed to trigger e2e pipelines thru `IntegrationTestScenarios`.
* The `ServiceAccount` and the required `Roles` and `RoleBindings` are managed via Tenants Config here:
  * https://gitlab.cee.redhat.com/releng/konflux-release-data/-/tree/main/staging/tenants-config/cluster/stone-stg-rh01/tenants/dev-release-team-tenant?ref_type=heads
  * https://gitlab.cee.redhat.com/releng/konflux-release-data/-/tree/main/staging/tenants-config/cluster/stone-stg-rh01/managed/managed-release-team-tenant?ref_type=heads
* `ServiceAccount` `Secrets` cannot be managed via Tenants Config, so we have to create the `Secret` manually in order to obtain a token:

```shell
kubectl create -f integration-tests/setup/resources/tenant/service_account_token.yaml
```

# e2e setup for Konflux RH01 Production
* Now that the `ServiceAccount` is set up on Konflux RH01 Staging, we can set up the environment for triggering the
IntegrationTestScenarios.
## e2e test secrets
* The following secrets are maintained in the Vault at https://vault.devshift.net/ui/vault/secrets/stonesoup/kv/list/staging/release/e2e/
  * e2e-base-github-token
  * e2e-test-service-account-kubeconfig (see next section)
  * vault-password
* They are deployed via Tenant Config at https://gitlab.cee.redhat.com/releng/konflux-release-data/-/tree/main/tenants-config/cluster/stone-prd-rh01/tenants/rhtap-release-2-tenant/es?ref_type=heads
## Updating e2e-test-service-account-kubeconfig
* login to Konflux RH01 Staging using the Service Account
* run the following script:

```shell
sh integration-tests/setup/scripts/get-kubeconfig-from-service-account.sh
```

* Copy the contents of the file `kubeconfig-sa` to the Vault at https://vault.devshift.net/ui/vault/secrets/stonesoup/kv/staging%2Frelease%2Fe2e%2Fe2e-test-service-account-kubeconfig/details?version=1
