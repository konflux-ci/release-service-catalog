# collect-data

Tekton task to collect the information added to the extraData field of the release resources.

The purpose of this task is to collect all the extra data and supply it to the other task in the pipeline through
a Tekton result. The name of this result is `extraData`.

This task also has the ability to store the passed resources as json in a workspace.

## Parameters

| Name                 | Description                                        | Optional | Default value |
|----------------------|----------------------------------------------------|----------|---------------|
| release              | Namespaced name of the Release                     | No       | -             |
| releasePlan          | Namespaced name of the ReleasePlan                 | No       | -             |
| releasePlanAdmission | Namespaced name of the ReleasePlanAdmission        | No       | -             |
| releaseStrategy      | Namespaced name of the ReleaseStrategy             | No       | -             |
| snapshot             | Namespaced name of the Snapshot                    | No       | -             |

## Changes since 0.1

* The releaseStrategy's namespaced name is now also passed as a parameter.
* The snapshot's namespaced name is now also passed as a parameter.
* Each of the passed CRs are stored as json in the workspace.
