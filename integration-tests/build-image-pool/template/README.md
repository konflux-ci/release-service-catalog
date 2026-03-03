# Large Snapshot Template

Self-contained template for rh-advisories-large-snapshot component repos. Used by
`build-images.sh` when creating `rh-adv-large-{component}` repos.

**No dependency on e2e-base.** When this template exists, `build-images.sh` uses it
instead of copying from `hacbs-release-tests/e2e-base`.

## Contents

- `.tekton/template-push.yaml` - Push-only PAC config (multi-arch)
- `Dockerfile` - Base image; size customized per component by build-images.sh

## Placeholders (replaced by build-images.sh)

- `template-component` → component name (e.g. v4-15-apiserver-watcher-01)
- `large-snapshot-build-template` → large-snapshot-build-{version}
- `large-snapshot-template` → main
