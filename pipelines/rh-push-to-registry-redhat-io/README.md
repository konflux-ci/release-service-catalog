# rh-push-to-registry-redhat-io pipeline

Tekton pipeline to release content to registry.redhat.io registry.

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
| taskGitUrl | The url to the git repo where the release-service-catalog tasks to be used are stored | Yes | https://github.com/redhat-appstudio/release-service-catalog.git |
| taskGitRevision | The revision in the taskGitUrl repo to be used | No | - |

## Changes in 3.1.1
* Added a `when` clause to the following tasks
  `rh-sign-image`,
  `create-pyxis-image`
  `collect-pyxis-params` and
  `run-file-updates`
  to ensure they only execute when the `push-snapshot`
  task result indicates that `commonTags` is not an empty string

## Changes in 3.1.0
* Remove push-sbom-to-pyxis. It has been replaced by manifest-box.

## Changes in 3.0.0
* releaseServiceConfig added as a pipeline parameter that is passed to the collect-data task

## Changes in 2.0.0
* Parameters supplied by the Release Service operator now use camelCase format

## Changes in 1.9.0
* Modified the pipeline to dynamically source the `data.json`, `snapshot_spec.json` and
  `release_plan_admission.json` files from the results of the `collect-data` task.

## Changes in 1.8.1
* Tasks that interact with InternalRequests now have a pipelineRunUid parameter added to them to help with cleanup

## Changes in 1.8.0
* taskGitRevision no longer has a default. It will be provided by the operator and will always have the same value as
  the git revision in the PipelineRef definition of the PipelineRun if using a git resolver. See RHTAPREL-790 for details

## Changes in 1.7.0
* taskGitUrl parameter is added. It is used to provide the git repo for the release-service-catalog tasks
* taskGitRevision parameter is added. It is used to provide the revision to be used in the taskGitUrl repo

## Changes in 1.6.0
* The publish-pyxis-repository task now has a dataPath parameter. It is used to set 
  source_container_image_enabled if `pushSourceContainer` is present in the data `images` key
  and set to true

## Changes since 1.4.2
* Move from commonTag to commonTags
  - The result of push-snapshot was renamed to commonTags and now it contains both the fixed and floating
    tags, e.g. tagprefix-timestamp and tagprefix. The consuming tasks (rh-sign-image and create-pyxis-image)
    were also modified to take advantage of this

## Changes since 1.4.0
* The parameter `pushSourceContainer` in the `push-snapshot` task
  was not added correctly in the previous version, the new version
  fixes the issue.

## Changes since 1.3.0
* add parameter `pushSourceContainer` to `push-snapshot`, this will
  enable push of the source container image and fail the pipeline if the
  image is not available.

## Changes since 1.2.0
* Set rhPush and commonTag when calling create-pyxis-image task
* Add publish-pyxis-repository task

## Changes since 1.1.1
* Add tasks extract-requester-from-release and rh-sign-image so the pipeline can sign
  component images using the requester username

## Changes since 1.1.0
* Pass path to ReleasePlanAdmission to the apply-mapping task

## Changes since 1.0.0
* Switch back to using bundle resolvers for the verify-enterprise-contract task

## Changes since 0.1.0
* Removed tagPrefix, timestampFormat, tag, addGitShaTag, addSourceShaTag, addTimestampTag parameters
  - These are now provided in the data json that is collected in the collect-data task
