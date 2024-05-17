#!/bin/bash

# This script will install the CRDs used by the release-service
# to the cluster.
#
# Requirements:
# - Connection to a running k8s cluster (e.g. kind)

install_appstudio_repo_crds () {
    git clone https://github.com/$1/$2
    pushd $2
    kubectl apply -f config/crd/bases
    popd
}

if ! kubectl get crd snapshots.appstudio.redhat.com ; then
    install_appstudio_repo_crds "redhat-appstudio" "application-api"
fi

if ! kubectl get crd releases.appstudio.redhat.com ; then
    install_appstudio_repo_crds "konflux-ci" "internal-services"
fi

if ! kubectl get crd releases.appstudio.redhat.com ; then
    install_appstudio_repo_crds "konflux-ci" "release-service"
fi
