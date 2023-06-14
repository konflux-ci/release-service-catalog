# apply-mapping

Tekton task to collect the information added to the extraData field of the release resources.

The purpose of this task is to collect all the extra data and supply it to the other task in the pipeline through
a Tekton result. The name of this result is `extraData`.

## Parameters

| Name                 | Description                                        | Optional | Default value |
|----------------------|----------------------------------------------------|----------|---------------|
| release              | Namespaced name of the Release                     | No       | -             |
| releasePlan          | Namespaced name of the ReleasePlan                 | No       | -             |
| releasePlanAdmission | Namespaced name of the ReleasePlanAdmission        | No       | -             |
