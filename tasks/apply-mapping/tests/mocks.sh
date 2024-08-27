#!/usr/bin/env sh
set -eux

# mocks to be injected into task step scripts

function date() {
  echo $* >> $(workspaces.config.path)/mock_date.txt

  case "$*" in
      *"+%Y%m%d %T")
          echo "19800101 00:00:00"
          ;;
      *"+%s")
          echo "315550800"
          ;;
      *"+%Y-%m-%d")
          echo "1980-01-01"
          ;;
      *"+%Y-%m")
          echo "1980-01"
          ;;
      "*")
          echo Error: Unexpected call
          exit 1
          ;;
  esac
}

function kubectl() {

  if [[ "$*" == "get snapshot/"* ]]
  then
    SNAPSHOT_JSON=$(cat << EOF
{
  "apiVersion": "appstudio.redhat.com/v1alpha1",
  "kind": "Snapshot",
  "metadata": {
    "labels": {
      "appstudio.openshift.io/application": "golden-container",
      "appstudio.openshift.io/build-pipelinerun": "golden-container-on-push-rfjsw",
      "appstudio.openshift.io/component": "comp1",
      "pac.test.appstudio.openshift.io/check-run-id": "29271572623",
      "pac.test.appstudio.openshift.io/event-type": "push",
      "pac.test.appstudio.openshift.io/original-prname": "golden-container-on-push",
      "pac.test.appstudio.openshift.io/repository": "golden-container",
      "pac.test.appstudio.openshift.io/sha": "0c0846586598288647d220a7cc71045336ee0eed",
      "pac.test.appstudio.openshift.io/state": "completed",
      "pac.test.appstudio.openshift.io/url-org": "enterprise-contract",
      "pac.test.appstudio.openshift.io/url-repository": "golden-container",
      "test.appstudio.openshift.io/pipelinerunfinishtime": "1724700599",
      "test.appstudio.openshift.io/type": "component"
    },
    "name": "golden-container-4plgp",
    "namespace": "rhtap-contract-tenant"
  }
}
EOF
    )
    echo $SNAPSHOT_JSON
    exit 0
  fi

  echo Error: Unexpected call
  exit 1
}


