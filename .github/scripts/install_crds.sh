#!/bin/bash

# This script will install the CRDs used by the release-service
# to the cluster.
#
# Requirements:
# - Connection to a running k8s cluster (e.g. kind)

install_appstudio_repo_crds () {
    git clone https://github.com/redhat-appstudio/$1
    pushd $1
    kubectl apply -f config/crd/bases
    popd
}

if ! kubectl get crd snapshots.appstudio.redhat.com ; then
    install_appstudio_repo_crds "application-api"
fi
if ! kubectl get crd releases.appstudio.redhat.com ; then
    install_appstudio_repo_crds "release-service"
fi
