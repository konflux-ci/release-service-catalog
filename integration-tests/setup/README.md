# e2e setup

## Service Account

A `ServiceAccount` is needed to run e2e pipelines via `IntegrationTestScenarios`.
The `ServiceAccount` and the required `Roles` and `RoleBindings` are managed via
Tenants Config:

* https://gitlab.cee.redhat.com/releng/konflux-release-data/-/tree/main/staging/tenants-config/cluster/stone-stg-rh01/tenants/dev-release-team-tenant
* https://gitlab.cee.redhat.com/releng/konflux-release-data/-/tree/main/staging/tenants-config/cluster/stone-stg-rh01/managed/managed-release-team-tenant

Periodics and ITS run in-cluster; no kubeconfig or SA token Secret is required.
