#!/bin/bash

(return 0 2>/dev/null) && sourced=1 || sourced=0
if [ "${sourced}" -eq 0 ]; then
  echo "ERROR: This script must be sourced since it needs to be able to export environment variables"
  echo "% . ./deploy_registry.sh"
  exit 1
fi

script_path="$(dirname -- "${BASH_SOURCE[0]}")"

retry() {
  for _ in {1..3}; do
      local ret=0
      $1 || ret="$?"
      if [[ "$ret" -eq 0 ]]; then
          return 0
      fi
      sleep 3
  done

  echo "$1": "$2."
  return "$ret"
}

deploy_cert_manager() {
  # Download cert-manager.yaml first - kustomize misinterprets github.com release URLs as git repos
  curl -sL https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml \
    -o "${script_path}/../resources/cert-manager/cert-manager.yaml"
  kubectl apply -k "${script_path}/../resources/cert-manager"
  sleep 5
  retry "kubectl wait --for=condition=Ready --timeout=120s -l app.kubernetes.io/instance=cert-manager -n cert-manager pod" \
        "Cert manager did not become available within the allocated time"
}

deploy_trust_manager() {
  kubectl apply -k "${script_path}/../resources/trust-manager"
  sleep 5
  # trust manager is running in the cert-manager namespace
  retry "kubectl wait --for=condition=Ready --timeout=60s -l app.kubernetes.io/instance=trust-manager -n cert-manager pod" \
        "Trust manager did not become available within the allocated time"
}

deploy_registry() {
  kubectl apply -k "${script_path}/../resources/registry"
  sleep 5
  retry "kubectl wait --for=condition=Ready --timeout=240s -n kind-registry -l run=registry pod" \
        "The local registry did not become available within the allocated time"
}

port_forward() {
  regpid=$(ps -eawwf | grep "30001:443" | grep -v grep | awk '{print $2}')
  if [ ! -z "$regpid" ] ; then
    kill -9 $regpid
  fi
  sleep 2

  kubectl port-forward -n kind-registry svc/registry-service 30001:443 &
}

prepare_docker_config() {
  authString=$(echo -n "root:root" | base64 -w0)
  dockerconfigFile="$(mktemp -d)/.dockerconfig.json"
  cat > "${dockerconfigFile}" <<EOF
  {
    "auths": {
      "registry-service.kind-registry": {
        "auth": "${authString}"
      }
    }
  }
EOF
  export DOCKER_CONFIG_JSON=${dockerconfigFile}
}

deploy_cert_manager
deploy_trust_manager
kubectl apply -k "${script_path}/../resources/cluster-issuer"
deploy_registry
port_forward
prepare_docker_config
