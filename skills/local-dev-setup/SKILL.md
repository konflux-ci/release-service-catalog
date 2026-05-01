---
name: local-dev-setup
description: Use when onboarding to this repo, cloning for the first time, resetting a dev environment, or an agent needs to set up a working local instance.
---

# Local Development Setup

## Prerequisites

- [kind](https://kind.sigs.k8s.io/) (for local Kubernetes cluster)
- [Docker](https://docs.docker.com/get-docker/)
- [Git](https://git-scm.com/)

## Clone & Setup

```bash
git clone https://github.com/konflux-ci/release-service-catalog.git
cd release-service-catalog
```

## Kind Cluster Setup

```bash
# Create a local Kubernetes cluster
kind create cluster --name dev-cluster

# Verify it's running
kubectl cluster-info --context kind-dev-cluster
```

To tear down:
```bash
kind delete cluster --name dev-cluster
```

## IDE Setup

If using Cursor or VS Code, the repo may include:
- `.cursor/rules/` -- AI coding rules
- `.vscode/` -- editor settings
- `.editorconfig` -- formatting rules
