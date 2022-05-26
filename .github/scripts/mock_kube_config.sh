#!/bin/bash
printf 'Creating mock kube config for TKN cli\n'
mkdir -vp $HOME/.kube || true
cat <<-EOF > $HOME/.kube/config
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: _
  name: _
contexts:
- context:
    cluster: _
  name: _
current-context: _
EOF