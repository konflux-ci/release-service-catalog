#!/usr/bin/env bash

# Create a dummy exodus secret (and delete it first if it exists)
kubectl delete secret pulp-task-exodus-secret --ignore-not-found
kubectl create secret generic pulp-task-exodus-secret --from-literal=cert=myexoduscert --from-literal=key=myexoduskey --from-literal=url=https://exodus.com

# Create a dummy pulp secret (and delete it first if it exists)
kubectl delete secret pulp-task-pulp-secret --ignore-not-found
kubectl create secret generic pulp-task-pulp-secret --from-literal=konflux-release-rhsm-pulp.crt=mypulpcert --from-literal=konflux-release-rhsm-pulp.key=mypulpkey --from-literal=pulp_url=https://pulp.com

# Create a dummy udc secret (and delete it first if it exists)
kubectl delete secret pulp-task-udc-secret --ignore-not-found
kubectl create secret generic pulp-task-udc-secret --from-literal=cert=myudccert --from-literal=key=myudckey --from-literal=url=https://udc.com

# Create a dummy cgw secret (and delete it first if it exists)
kubectl delete secret pulp-task-cgw-secret --ignore-not-found
kubectl create secret generic pulp-task-cgw-secret --from-literal=username=cgwuser --from-literal=token=cgwtoken

# Create a dummy workloads secret (and delete it first if it exists)
# The secret name here is hardcoded in the task
# NOTE: the --from-literal value must stay single-quoted -- otherwise bash's
# unquoted double quotes get stripped by word-splitting, corrupting this into
# invalid JSON ({auths:{quay.io:{auth:abcdefg}}}) that authentication.py's
# strict JSON validation (setup_docker_config) correctly rejects.
kubectl delete secret redhat-workloads-token --ignore-not-found
kubectl create secret generic redhat-workloads-token --from-literal='.dockerconfigjson={"auths":{"quay.io":{"auth":"abcdefg"}}}'
