# Push to External Registry - Self-Hosted Quay

This test verifies that the `push-to-external-registry` pipeline works correctly
with a self-hosted Quay registry instance.

## Overview

Unlike other e2e tests that run against the staging Konflux cluster, this test
uses an ephemeral Kind cluster with a self-hosted Quay deployment. Quay is
deployed as part of the Konflux deployment, and the test script handles all
initialization (admin user, org, robot account, image copy).

## Prerequisites

The test expects the following to be available in the Kind cluster:

- **Konflux deployed** via the `deploy-konflux-ci` task with `skip-quay=false`
  and `SKIP_QUAY_ADMIN_INIT=true`
- **Quay pods running** (Postgres, Redis, Quay) in the `quay` namespace

The test script (`test-kind.sh`) handles all Quay initialization itself.

## How It Works

The test (`test-kind.sh`) performs the following steps:

1. Initializes Quay (creates admin user, organization, robot account via API)
2. Copies a source image into Quay via an in-cluster `cosign copy` pod
3. Creates isolated dev and managed namespaces
4. Creates registry secrets from Quay robot credentials
5. Applies Kubernetes resource templates (Application, ReleasePlan,
   ReleasePlanAdmission, EnterpriseContractPolicy, ServiceAccount, PVC, RBAC)
6. Creates a Snapshot CR with the copied image to trigger the release
7. Waits for the Release CR and PipelineRun to complete
8. Verifies the Release is marked as succeeded

## Pipeline

This test is run by `integration-tests/pipelines/e2e-tests-kind-quay-pipeline.yaml`,
which orchestrates:

1. Provision a Kind cluster on AWS
2. Deploy Konflux with Quay enabled
3. Run this test (which initializes Quay and triggers the release)
4. Deprovision the cluster
