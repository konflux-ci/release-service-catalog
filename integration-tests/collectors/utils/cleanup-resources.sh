#!/usr/bin/env bash
#
# Summary:
#   This script generates a separate cleanup shell script located at /tmp/cleanup.sh.
#   The generated script contains a series of 'kubectl delete' commands designed to
#   remove specific Kubernetes resources from two hardcoded namespaces:
#   'dev-release-team-tenant' (referred to as tenant_namespace) and
#   'managed-release-team-tenant' (referred to as managed_namespace).
#
#   It targets resources that typically include "collector-" or "e2eapp-" in their names.
#
#   The script first sets the kubectl context to the 'managed_namespace' and generates
#   commands to delete:
#     - ServiceAccounts (sa)
#     - Secrets
#     - ReleasePipelineAdmissions (rpa)
#     - EnterpriseContractPolicies
#     - RoleBindings
#   (all filtered by names containing "collector-").
#
#   Then, it switches the kubectl context to the 'tenant_namespace' and generates
#   commands to delete:
#     - Applications (filtered by names containing "e2eapp-")
#     - Components
#     - ReleasePlans (rp)
#     - RoleBindings
#     - ServiceAccounts (sa)
#     - Secrets
#   (all filtered by names containing "collector-").
#
#   Finally, it instructs the user to execute the generated /tmp/cleanup.sh script.
#
# Parameters:
#   None. Namespace names are hardcoded within the script.
#
# Environment Variables:
#   KUBECONFIG (Implicitly used by kubectl) - Path to the Kubernetes configuration file.
#
# Dependencies:
#   kubectl, awk, grep, tee
#
# Output:
#   - Creates/overwrites a shell script at /tmp/cleanup.sh containing kubectl delete commands.
#   - Prints a message to the console guiding the user to run /tmp/cleanup.sh.

# Use this periodically to produce a cleanup script

# Use this periodically to produce a cleanup script

tenant_namespace=dev-release-team-tenant
managed_namespace=managed-release-team-tenant

kubectl config set-context --current --namespace=$managed_namespace
echo "kubectl config set-context --current --namespace=$managed_namespace" | tee /tmp/cleanup.sh
kubectl get sa --no-headers | grep collector- | awk '{print "kubectl delete sa/"$1}' | tee -a /tmp/cleanup.sh
kubectl get secret --no-headers | grep collector- | awk '{print "kubectl delete secret/"$1}' | tee -a /tmp/cleanup.sh
kubectl get rpa --no-headers | grep collector- | awk '{print "kubectl delete rpa/"$1}' | tee -a /tmp/cleanup.sh
kubectl get enterprisecontractpolicy --no-headers | grep collector- | awk '{print "kubectl delete enterprisecontractpolicy/"$1}' | tee -a /tmp/cleanup.sh
kubectl get rolebinding --no-headers | grep collector- | awk '{print "kubectl delete rolebinding/"$1}' | tee -a /tmp/cleanup.sh

kubectl config set-context --current --namespace=$tenant_namespace
echo "kubectl config set-context --current --namespace=$tenant_namespace" | tee -a /tmp/cleanup.sh
kubectl get application --no-headers | grep e2eapp- | awk '{print "kubectl delete application/"$1}' | tee -a /tmp/cleanup.sh
kubectl get component --no-headers | grep collector- | awk '{print "kubectl delete component/"$1}' | tee -a /tmp/cleanup.sh
kubectl get rp --no-headers | grep collector- | awk '{print "kubectl delete rp/"$1}' | tee -a /tmp/cleanup.sh
kubectl get rolebinding --no-headers | grep collector- | awk '{print "kubectl delete rolebinding/"$1}' | tee -a /tmp/cleanup.sh
kubectl get sa --no-headers | grep collector- | awk '{print "kubectl delete sa/"$1}' | tee -a /tmp/cleanup.sh
kubectl get secret --no-headers | grep collector- | awk '{print "kubectl delete secret/"$1}' | tee -a /tmp/cleanup.sh

echo "You can now run:  sh /tmp/cleanup.sh"
