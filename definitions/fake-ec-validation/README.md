# validate-enterprise-contract

Tekton task to fake an Enterprise Contract validation.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| applicationSnapshot | JSON representation of the ApplicationSnapshot being released | Yes | - |
| policy | Name of the policy to apply when validating the enterprise contract | Yes | - |
| shouldFail | Whether the validation should fail or not | Yes | "false" |

## Example usage

This is an example usage of the `validate-enterprise-contract` task:

```
---
tasks:
  - name: validate-enterprise-contract
    taskRef:
      name: validate-enterprise-contract
    params:
      - name: shouldFail
        value: "true"
```
