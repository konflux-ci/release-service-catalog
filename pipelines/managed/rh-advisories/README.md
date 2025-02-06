# rh-advisories pipeline

Tekton pipeline to release content to registry.redhat.io registry and create an advisory.
This is a copy of v3.0.0 of the rh-push-to-registry-redhat-io pipeline, but with the advisory
tasks added in. The plan is for this pipeline to eventually be deleted and take the place of
the rh-push-to-registry-redhat-io pipeline.

## Parameters

| Name                            | Description                                                                                                                        | Optional | Default value                                             |
|---------------------------------|------------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| release                         | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution                             | No       | -                                                         |
| releasePlan                     | The namespaced name (namespace/name) of the releasePlan                                                                            | No       | -                                                         |
| releasePlanAdmission            | The namespaced name (namespace/name) of the releasePlanAdmission                                                                   | No       | -                                                         |
| releaseServiceConfig            | The namespaced name (namespace/name) of the releaseServiceConfig                                                                   | No       | -                                                         |
| snapshot                        | The namespaced name (namespace/name) of the snapshot                                                                               | No       | -                                                         |
| enterpriseContractPolicy        | JSON representation of the policy to be applied when validating the enterprise contract                                            | No       | -                                                         |
| enterpriseContractExtraRuleData | Extra rule data to be merged into the policy specified in params.enterpriseContractPolicy. Use syntax "key1=value1,key2=value2..." | Yes      | pipeline_intention=release                                |
| enterpriseContractTimeout       | Timeout setting for `ec validate`                                                                                                  | Yes      | 8h0m0s                                                    |
| enterpriseContractWorkerCount   | Number of parallel workers to use for policy evaluation.                                                                           | Yes      | 4                                                         |
| postCleanUp                     | Cleans up workspace after finishing executing the pipeline                                                                         | Yes      | true                                                      |
| verify_ec_task_bundle           | The location of the bundle containing the verify-enterprise-contract task                                                          | No       | -                                                         |
| taskGitUrl                      | The url to the git repo where the release-service-catalog tasks to be used are stored                                              | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision                 | The revision in the taskGitUrl repo to be used                                                                                     | No       | -                                                         |

## Changes in 1.11.0
* Add new task `close-advisory-issues` to close all issues listed in the releaseNotes after the advisory is published

## Changes in 1.10.0
* Add new task `set-advisory-severity` to run after `populate-release-notes` that will inject a severity
  key into the releaseNotes in the data file based on the releaseNotes.type and CVEs present

## Changes in 1.9.0
* Task `populate-release-notes-images` renamed to `populate-release-notes`

## Changes in 1.8.4
* Pass taskGitUrl and taskGitRevision to create-advisory task

## Changes in 1.8.3
* Pass taskGitUrl and taskGitRevision to run-file-updates task

## Changes in 1.8.2
* Pass taskGitUrl and taskGitRevision to embargo-check task

## Changes in 1.8.1
* Set timeout for rh-sign-image-cosign task to be 6 hrs

## Changes in 1.8.0
* Update all task pathInRepo values as they are now in `tasks/managed`

## Changes in 1.7.0
* Add collect-atlas-params task to fetch Atlas parameters from the RPA.
* Add create-product-sbom task to create product-level SBOMs.
* Add update-component-sbom task to update component-level SBOMs with release
  info.
* Add upload-product-sbom task to push the product SBOM to Atlas.
* Add upload-component-sbom task to push the component-level SBOMs to Atlas.

## Changes in 1.6.0
* Add new parameter `schema` to the `check-data-keys` task.
* Add new systems pyxis,mapping & signing to the task.

## Changes in 1.5.7
* new mandatory parameter `dataPath` added to `create-pyxis-image` task

## Changes in 1.5.6
* new mandatory parameter resultsDirPath added to run-file-updates task

## Changes in 1.5.5
* Add retries to apply-mapping task in case of transient errors

## Changes in 1.5.4
* Increase task timeout on the verify-enterprise-contract task

## Changes in 1.5.3
* Increase enterpriseContractTimeout to a large value, 8 hours.
  * Users don't have control over this, so set it to a large value so that the pipeline timeout will kick in first, if anything.

## Changes in 1.5.2
* Make sure `create-advisory` runs late in the pipeline
  * Task `create-advisory` would run after `publish-pyxis-repository` which
    would ensure it runs late in the pipeline. But with the changes in 1.5.0,
    `publish-pyxis-repository` runs much earlier now.
  * So make `create-advisory`
    run after `push-rpm-data-to-pyxis` which is what `publish-pyxis-repository`
    ran after originally.
  * But also, add a few more `runAfter` entries to make it run as late
    as possible:
    * `run-file-updates`
    * `rh-sign-image`
    * `rh-sign-image-cosign`
* Make some other tasks' order more explicit
  * No functional change, the tasks already depended on the other tasks'
    results, but this makes it more explicit (and Tekton PLR UI
    is known to show incorrect order when relying on task results only)


## Changes in 1.5.1
* Task `publish-pyxis-repository` should only run after `apply-mapping` has completed as it depends on the `repository`
  value

## Changes in 1.5.0
* Only sign `registry.access*` references if required
  * Task `publish-pyxis-repository` has a new `signRegistryAccessPath` result that is passed
    to tasks `rh-sign-image` and `rh-sign-image-cosign`. It points to a file that contains a list of repositories
    for which we also need to sign `registry.access*` references. We will skip those by default.
  * Some task reordering was required for this:
    * We run `rh-sign-image` before `push-snapshot` because it's less reliable. We want to keep this.
    * `publish-pyxis-repository` was run towards the end, but now it needs to run early on,
      because`rh-sign-image` needs its result.

## Changes in 1.4.0
* Increase timeout for rh-sign-image task to be 6 hrs
* Add new mandatory parameter value for releasePlanAdmissionPath for rh-sign-image task
* Add new parameter values for taskGit* parameters.
* Introduce new optional parameter `enterpriseContractWorkerCount` to increase performance of ec verify task

## Changes in 1.3.2
* Add retries for some tasks

## Changes in 1.3.1
* Increase timeout for signing IRs from 20 to 30 min
  * We got reports from users that they repeatedly see timeouts here

## Changes in 1.3.0
* Add new reduce-snapshot task

## Changes in 1.2.0
* The `push-rpm-manifest-to-pyxis` task is renamed to `push-rpm-data-to-pyxis`

## Changes in 1.1.0
* The `publish-pyxis-repository` now gets the `resultsDirPath` parameter from the `collect-data` results

## Changes in 1.0.1
* Increase `rh-sign-image` timeout from 600s to 1200s as we have seen reports
  of it timing out while waiting for internalRequests to complete.

## Changes in 1.0.0
* Drop the `enterpriseContractPublicKey` param. The verify task will take the value from the policy.

## Changes in 0.14.0
* Add `requireInternalServices` parameter to the 'verify-access-to-resources' task.

## Changes in 0.13.3
* Bugfix: block pipeline progress on the verify-enterprise-contract.

## Changes in 0.13.2
* Increase `enterpriseContractTimeout` parameter default value.

## Changes in 0.13.1
* Add `enterpriseContractTimeout` parameter.

## Changes in 0.13.0
* Add tasks `collect-cosign-params` and `rh-sign-image-cosign` to sign images by cosign. `rh-sign-image-cosign` is only run if sign.cosignSecretName is set in the data file.

## Changes in 0.12.0
* Removed `verify-access-to-resources` script and replaced it with a task

## Changes in 0.11.1
* The `embargo-check` task runs before the `push-snapshot` task so that embargoed content is not pushed anywhere

## Changes in 0.11.0
* The `rh-sign-image` task no longer receives the `commonTags` parameter
* The `populate-release-notes-images` task no longer receives the `commonTags` parameter
* The `create-pyxis-image` task no longer receives the `commonTags` nor `dataPath` parameter

## Changes in 0.10.0
* The `push-snapshot` task now gets the `resultsDirPath` parameter from the `collect-data` results

## Changes in 0.9.0
* Add the task `update-cr-status` at the end of the pipeline to save all pipeline results

## Changes in 0.8.0
* The create-advisory task now gets the `resultsDirPath` parameter from the collect-data results

## Changes in 0.7.1
* The when conditions that skipped tasks if the `push-snapshot` result `commonTags` was empty was removed
  * This is due to the migration to the new tag format. A similar when will be readded with RELEASE-932

## Changes in 0.7.0
* The apply-mapping task now gets the dataPath parameter instead of releasePlanAdmissionPath

## Changes in 0.6.0
* `enterpriseContractExtraRuleData` added as a pipeline parameter, which is
  then passed to EC. Allows for easier runtime changes to rule data.

## Changes in 0.5.1
* The RADAS timeout when it fails to receive a response is 5 mins.
  We double the requestTimeout in the rh-sign-image task to allow
  RADAS to retry its request.

## Changes in 0.5.0
* Add new task `push-rpm-manifests-to-pyxis` to run after `create-pyxis-image`

## Changes in 0.4.0
* update the taskGitUrl default value due to migration
  to konflux-ci GitHub org

## Changes in 0.3.1
* Added `when` clause to `push-snapshot` task in the pipeline
  to ensure it only executes when
  the `apply-mapping` task indicates that mapping was successful.

## Changes in 0.3.0
* Add task `embargo-check` to end execution early if any passed issues or CVEs are embargoed.

## Changes in 0.2.2
* Added a `when` clause to the following tasks
  `create-advisory`, and `check-data-keys`
  to ensure they only execute when the `push-snapshot`
  task result indicates that `commonTags` is not an empty string

## Changes in 0.2.1
* Added a `when` clause to the following tasks
  `rh-sign-image`,
  `populate-release-notes-images`,
  `create-pyxis-image`,
  `collect-pyxis-params` and
  `run-file-updates`
  to ensure they only execute when the `push-snapshot`
  task result indicates that `commonTags` is not an empty string

## Changes in 0.2.0
* Remove push-sbom-to-pyxis. It has been replaced by manifest-box.
