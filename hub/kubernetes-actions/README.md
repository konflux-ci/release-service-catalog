# kubernetes-actions

**This task is a copy of an upstream task. The upstream task is located at
https://github.com/tektoncd/catalog/tree/main/task/kubernetes-actions**

This task is the generic kubectl CLI task which can be used to run all kinds of k8s commands.

## Parameters

| Name | Description                         | Optional | Default value |
|------|-------------------------------------|----------|---------------|
| script | The Kubernetes CLI script to run  | Yes      | kubectl $@    |
| args | The Kubernetes CLI arguments to run | Yes      | help          |
| image | Kubectl wrapper image              | Yes      | gcr.io/cloud-builders/kubectl@sha256:8ab94be8b2b4f3d117f02d868b39540fddd225447abf4014f7ba4765cb39f753 |

## Changes in 0.2
* update Tekton API to v1