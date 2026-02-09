# update-released-snapshot

Syncs the promoted Koji build into the integration snapshot in the releng-integration-tenant namespace.

## When it runs

This task runs **after** `promote-koji-draft-build` (and after `update-package-collection-after-promote-draft-build`) in the **promote** path of:

- `pipelines/managed/push-rpm-to-koji`
- `pipelines/managed/push-artifacts-to-storage`

It only runs when `pushType` is `"promote"`.

## What it does

1. Reads the Snapshot spec and data from the workspace (dev snapshot that triggered the release).
2. Derives **application names** from package-collections (package-collection name with `.` replaced by `-`, e.g. `rhel-10.1.z` → `rhel-10-1-z`). Uses the same logic as the promotion task (koji tag from container image annotation + mapping package-collections).
3. Fetches the **full Snapshot CR** from the dev namespace (e.g. `rhel-osci-tenant`) to copy metadata (annotations, labels) and status.
4. For each application name, in **releng-integration-tenant**:
   - Verifies the Application exists.
   - Builds an integration Snapshot: metadata from dev (with name = application name, namespace = integration tenant), spec.application = application name, spec.components = dev snapshot components (latest RPM OCI), status from dev.
   - If a Snapshot with that name exists → patches it with the new spec and status.
   - Otherwise → creates a new Snapshot with that name and the RPM components.

## Parameters

| Name                   | Description                                                                 | Optional | Default                     |
|------------------------|-----------------------------------------------------------------------------|----------|-----------------------------|
| snapshotPath           | Path to the Snapshot spec JSON in the data workspace                        | No       | -                           |
| dataPath               | Path to the merged data JSON in the data workspace                          | No       | -                           |
| snapshotName           | Name of the Snapshot in the dev namespace                                   | No       | -                           |
| snapshotNamespace      | Dev namespace (e.g. rhel-osci-tenant)                                       | No       | -                           |
| integrationNamespace   | Integration tenant namespace                                                | Yes      | releng-integration-tenant   |
| pushSecret             | Secret for OCI registry auth (oras)                                        | No       | -                           |
| pipelineImage          | Image with oras, jq, kubectl                                                | No       | -                           |
| ociStorage             | OCI repository for Trusted Artifacts                                       | Yes      | empty                       |
| sourceDataArtifact     | Trusted artifact location for workspace                                     | Yes      | ""                          |
| trustedArtifactsDebug  | Enable debug logging for trusted artifacts                                  | Yes      | ""                          |
| orasOptions            | Options for oras                                                            | Yes      | ""                          |
| dataDir                | Data directory in workspace                                                 | Yes      | /var/workdir/release        |
| taskGitUrl             | Git URL for release-service-catalog                                        | No       | -                           |
| taskGitRevision        | Git revision for release-service-catalog                                   | No       | -                           |

## Testing

- Test tenant: **rhel-osci-tenant** (dev namespace where the snapshot triggers the release).
- Target: **releng-integration-tenant** (e.g. Konflux UI `.../ns/releng-integration-tenant`).
- Snapshot name in integration = application name (e.g. `rhel-10-1-z`).

## RBAC

The task must run with a ServiceAccount that can:

- **get** Snapshot in the dev namespace.
- **get** Application in the integration namespace.
- **get**, **patch**, **create** Snapshot in the integration namespace.
