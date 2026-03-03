# build-image-pool

Builds and maintains the pool of multi-arch images used by the `rh-advisories-large-snapshot`
integration test.

## What it does

Creates Konflux components, triggers multi-arch (or single-arch) builds, and writes the resulting
image digests to `rh-advisories-large-snapshot/resources/static-image-pool-stable.txt`. That file
is consumed by the test pipeline (`rh-advisories-large-snapshot`) to generate the large snapshot
without rebuilding. The static pool lives with the test since it is the test's primary input.

## Structure

```
build-image-pool/
├── utils/
│   ├── build-images.sh              # Main script: creates components, triggers builds
│   ├── check-and-retrigger-builds.sh # Checks build status, retriggers failed ones
│   ├── validate-and-collect-images.sh # Validates images and collects digests
│   └── quick-image-report.sh        # Quick status report of the image pool
└── template/
    ├── Dockerfile                   # Template Dockerfile used for each component
    └── .tekton/template-push.yaml   # PAC push pipeline template (multi-arch capable)
```

## PAC Triggers

Trigger via PR comment on `konflux-ci/release-service-catalog` (target branch: `development`):

| Comment | What it does |
|---|---|
| `/build-image-pool` | Incremental build — add missing components to reach 200 |
| `/build-image-pool --force` | Force-rebuild ALL 200 components from scratch |
| `/build-image-pool --count=N` | Build/fill to exactly N components |
| `/build-image-pool --single-arch` | Build amd64-only (faster, ~4× less signing load) |
| `/build-image-pool --prefix=XXX` | Build with custom component name prefix (default: `multi`) |

## Key Environment Variables (build-images.sh)

| Variable | Default | Description |
|---|---|---|
| `COMPONENT_COUNT` | `200` | Total images to build |
| `PRODUCT_VERSIONS` | `7` | Number of OCP versions to simulate (4.15–4.21) |
| `BUILD_ARCH_MODE` | `multi` | `multi` (4 arches) or `single` (amd64 only) |
| `COMPONENT_NAME_PREFIX` | `multi` | Prefix for component names |
| `FORCE_REBUILD` | `false` | Rebuild even valid existing components |

## Pipeline

`integration-tests/pipelines/build-image-pool-pipeline.yaml`
