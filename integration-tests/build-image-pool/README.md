# build-image-pool

Builds and maintains the pool of single/multi-arch images used by the stress integration tests.

## What it does

Creates Konflux components and triggers multi-arch (or single-arch) builds until the target
component count is reached. The resulting image digests are written to a local file that can
be committed to the repository and consumed by stress/large-snapshot tests as a static image
pool — avoiding the need to rebuild images on every test run.

## Structure

```
build-image-pool/
├── utils/
│   ├── build-images.sh              # Main script: creates components, triggers builds
│   ├── check-and-retrigger-builds.sh # Checks build status, retriggers failed ones
│   ├── validate-and-collect-images.sh # Validates images and collects digests
│   └── quick-image-report.sh        # Quick status report: [namespace] [prefix]
└── template/
    ├── Dockerfile                   # Template Dockerfile used for each component
    └── .tekton/template-push.yaml   # PAC push pipeline template (multi-arch capable)
```

## PAC Trigger

Post `/build-image-pool` as a PR comment on `konflux-ci/release-service-catalog`
(target branch: `development`) to start a run with the following defaults:

| Setting | Default |
|---|---|
| Mode | Incremental — adds missing components, preserves valid existing ones |
| Target count (`COMPONENT_COUNT`) | 200 components |
| Architecture | Multi-arch (amd64 / arm64 / s390x / ppc64le) |
| Product versions | 7 (simulating OCP 4.15–4.21) |
| Force rebuild | No — existing components are reused |
| Quay image reuse | Yes — if a Quay image with a `:stable` tag is found, its digest is reused instead of triggering a new build |
| Component name prefix | `multi` → component: `multi-v4-15-apiserver-watcher-01`, repo: `img-pool-multi-v4-15-apiserver-watcher-01` |

To customise behaviour, edit the pipeline params in `.tekton/build-image-pool.yaml`
before posting the comment, or run `build-images.sh` locally with environment
variables (see examples below).

## Customising a Run (script / pipeline level)

Since PAC only supports a single fixed trigger, all tuning is done by setting
environment variables before calling `build-images.sh`, or by editing the
corresponding pipeline params in `.tekton/build-image-pool.yaml` before posting
the `/build-image-pool` comment.

| Variable / Pipeline param | Default | Description |
|---|---|---|
| `COMPONENT_COUNT` | `200` | Total images to build |
| `FORCE_REBUILD` | `false` | `true` → delete all existing components and rebuild from scratch |
| `BUILD_ARCH_MODE` | `multi` | `multi` (amd64/arm64/s390x/ppc64le) or `single` (amd64 only, ~4× faster) |
| `COMPONENT_NAME_PREFIX` | `multi` | Prefix for Konflux component names: `{PREFIX}-v{ver}-{base}-{nn}` (e.g. `multi-v4-15-apiserver-watcher-01`). The GitHub repo name additionally prepends `COMPONENT_REPO_PREFIX`: `img-pool-multi-v4-15-apiserver-watcher-01`. |
| `PRODUCT_VERSIONS` | `7` | Number of OCP versions to simulate (4.15–4.21) |

### Examples

```bash
# Prerequisites: export a GitHub PAT with 'repo' scope
export GITHUB_TOKEN=ghp_...

SCRIPT=integration-tests/build-image-pool/utils/build-images.sh

# --- Incremental (default) ---
# Add missing components until pool reaches 200, reuse existing Quay images
./$SCRIPT

# Incremental fill to a custom count (e.g. 50 for quick validation)
./$SCRIPT 50

# Incremental, but skip Quay image reuse (always trigger fresh builds for missing)
DISABLE_QUAY_REUSE=true ./$SCRIPT

# --- Architecture ---
# Single-arch only (linux/amd64) — ~4x faster, useful for quick iteration
BUILD_ARCH_MODE=single ./$SCRIPT

# Explicit multi-arch (default, for production pool)
BUILD_ARCH_MODE=multi ./$SCRIPT 200

# --- Force rebuild ---
# Delete ALL existing components and rebuild from scratch
FORCE_REBUILD=true ./$SCRIPT

# Force rebuild, single-arch, smaller count — fastest full refresh
FORCE_REBUILD=true BUILD_ARCH_MODE=single ./$SCRIPT 50

# --- Custom naming ---
# Use a custom prefix to avoid colliding with the production pool.
# Component name: test-v4-15-apiserver-watcher-01
# GitHub repo:    img-pool-test-v4-15-apiserver-watcher-01
COMPONENT_NAME_PREFIX=test ./$SCRIPT 20

# --- Custom output file ---
# Write image digests to a specific file instead of /tmp/images-pool-<ts>.txt
./$SCRIPT 200 dev-release-team-tenant /tmp/my-pool.txt

# --- Combine options ---
# 100 components, single-arch, custom prefix, output to a known file
COMPONENT_NAME_PREFIX=staging BUILD_ARCH_MODE=single \
  ./$SCRIPT 100 dev-release-team-tenant /tmp/staging-pool.txt
```

## Pipeline

`integration-tests/pipelines/build-image-pool-pipeline.yaml`
