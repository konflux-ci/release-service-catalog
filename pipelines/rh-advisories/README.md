# rh-advisories pipeline

Tekton pipeline to release content to registry.redhat.io registry and create an advisory.
This is a copy of v3.0.0 of the rh-push-to-registry-redhat-io pipeline, but with the advisory
tasks added in. The plan is for this pipeline to eventually be deleted and take the place of
the rh-push-to-registry-redhat-io pipeline.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| release | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution | No | - |
| releasePlan | The namespaced name (namespace/name) of the releasePlan | No | - |
| releasePlanAdmission | The namespaced name (namespace/name) of the releasePlanAdmission | No | - |
| releaseServiceConfig | The namespaced name (namespace/name) of the releaseServiceConfig | No | - |
| snapshot | The namespaced name (namespace/name) of the snapshot | No | - |
| enterpriseContractPolicy | JSON representation of the policy to be applied when validating the enterprise contract | No | - |
| enterpriseContractPublicKey | Public key to use for validation by the enterprise contract | Yes | k8s://openshift-pipelines/public-key |
| postCleanUp | Cleans up workspace after finishing executing the pipeline | Yes | true |
| verify_ec_task_bundle | The location of the bundle containing the verify-enterprise-contract task | No | - |
| taskGitUrl | The url to the git repo where the release-service-catalog tasks to be used are stored | Yes | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision | The revision in the taskGitUrl repo to be used | No | - |

## Changes in 0.5.0
- Add new task `push-rpm-manifests-to-pyxis` to run after `create-pyxis-image`

## Changes in 0.4.0
- update the taskGitUrl default value due to migration
  to konflux-ci GitHub org

## Changes in 0.3.1
- Added `when` clause to `push-snapshot` task in the pipeline
  to ensure it only executes when
  the `apply-mapping` task indicates that mapping was successful.

## Changes in 0.3.0
- Add task `embargo-check` to end execution early if any passed issues or CVEs are embargoed.

## Changes in 0.2.2
- Added a `when` clause to the following tasks
  `create-advisory`, and `check-data-keys`
  to ensure they only execute when the `push-snapshot`
  task result indicates that `commonTags` is not an empty string

## Changes in 0.2.1
- Added a `when` clause to the following tasks
  `rh-sign-image`,
  `populate-release-notes-images`,
  `create-pyxis-image`,
  `collect-pyxis-params` and
  `run-file-updates`
  to ensure they only execute when the `push-snapshot`
  task result indicates that `commonTags` is not an empty string

## Changes in 0.2.0
- Remove push-sbom-to-pyxis. It has been replaced by manifest-box.
