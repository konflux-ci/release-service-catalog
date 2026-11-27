# Maintaining the static image pool

Manual steps to populate
[`resources/static-image-pool-stable.txt`](resources/static-image-pool-stable.txt)
for the [rh-advisories-large-snapshot](README.md) integration test.

The pool file must list **200** images that are already built and pushed to stage Quay.
Images are added to the pool **manually**: for each one, create the Konflux component and
Git repo, wait for the build, verify the image in Quay, and add one line to the pool
file. This integration test does not build images or update that list during a run.

When the test runs, [`generate-large-snapshot.sh`](utils/generate-large-snapshot.sh)
only reads that file; it does not create images or change the list.

Each committed line looks like:

```text
quay.io/redhat-user-workloads-stage/dev-release-team-tenant/ls-v4-15-apiserver-watcher-01:stable
```

Tags (`:stable`) or digests (`@sha256:…`) are both accepted. Use `:stable` when the
Dockerfile includes `LABEL konflux.additional-tags="stable"`.

## What you are building

The pool simulates a large product snapshot: many Konflux components across
several OpenShift-style version numbers, each with a real build on stage Quay and
Tekton Chains signatures (needed for rh-advisories).

| Setting | Value used today |
|---|---|
| Total images | 200 |
| Tenant namespace | `dev-release-team-tenant` |
| Cluster | `stg-rh01` |
| Component name prefix | `ls` |
| Simulated product versions | 7 (OCP 4.15–4.21) |
| Architecture for the static list | **linux/amd64 only** (single-arch; matches the committed pool) |

Multi-arch builds (amd64, arm64, s390x, ppc64le) are possible for heavier
signing scenarios; the bundled list is single-arch.

## Naming and layout

**Applications** — one Konflux Application per simulated version:

- Names: `large-snapshot-build-v4-15` … `large-snapshot-build-v4-21`.
- Namespace: `dev-release-team-tenant`.
- About 28 components per version; the last version absorbs the remainder so the
  total is exactly 200.

**Components** — for each slot within a version:

1. Use a realistic base name (e.g. `apiserver-watcher`, `network-operator`,
   `runtime-config`, …).
2. Konflux component name: `ls-v{version}-{base}-{nn}` (version uses hyphens,
   e.g. `ls-v4-16-network-operator-05`).
3. Dedicated GitHub repo per component, e.g.
   `hacbs-release-tests/img-pool-ls-v4-16-network-operator-05`.
4. Dedicated git branch, e.g. `component-ls-v4-16-network-operator-05`.

**Dockerfile** — each image should resemble a plausible RHTAP component:

- Base: `registry.access.redhat.com/ubi9/ubi:latest`
- `LABEL name="rhtap/rh-advisories-component"`
- Payload **100–500 MB** (e.g. data written under `/opt/`) for non-trivial layers.
- `LABEL konflux.additional-tags="stable"` for the Quay `:stable` tag.

Use the template repository
<https://github.com/hacbs-release-tests/rh-adv-large-snapshot-template> (Dockerfile
and push-only PAC YAML) as a starting point for each component repo.

## Prerequisites

- `kubectl` on `stg-rh01`, namespace `dev-release-team-tenant`.
- GitHub **PAT** with `repo` scope (create/push repos and branches under
  `hacbs-release-tests`, merge PAC PRs). Export as `GITHUB_TOKEN` when using `gh` or
  git over HTTPS.
- Existing Konflux tenant setup used by other release integration tests.
- Optional: `gh`, `jq`, `yq`, `skopeo`, `curl`.

## Step-by-step: manually add one image to the pool

Work through these steps for **each** component. Do not add a line to
`static-image-pool-stable.txt` until step 6 passes.

**Step 1 — Create the GitHub repository**

1. In GitHub (`hacbs-release-tests`), create an empty repo
   `img-pool-{component}` (e.g. `img-pool-ls-v4-15-apiserver-watcher-01`).
2. Clone it locally.
3. Copy `Dockerfile` and `.tekton/` from
   <https://github.com/hacbs-release-tests/rh-adv-large-snapshot-template>.
4. Replace every placeholder: component name, Application
   `large-snapshot-build-v4-…`, namespace `dev-release-team-tenant`, output image
   `quay.io/redhat-user-workloads-stage/dev-release-team-tenant/{component}:latest`,
   and your component branch name (e.g. `component-ls-v4-15-apiserver-watcher-01`).
5. Set a unique image size in the Dockerfile (100–500 MB payload).
6. Configure **push-only**, **single-arch** (`docker-build-oci-ta`, `linux/x86_64`):
   remove on-pull-request PAC files; pin `task-buildah-oci-ta` to **0.7** on stage if
   needed; set `pipelinesascode.tekton.dev/cancel-in-progress: "false"`.
7. Create the component branch, commit, and push.

**Step 2 — Ensure the Konflux Application exists**

If missing, create `large-snapshot-build-v4-15` … `v4-21` in
`dev-release-team-tenant` (`kubectl apply` or the Konflux UI). Each Application
owns a slice of the ~200 component names for that OCP version.

**Step 3 — Create the SCM credential Secret**

**PAC SCM credentials (required on `img-pool-*` repos).** If PAC cannot use the GitHub
App on `img-pool-*` repos (clone failures, Error 70), create a **per-repo** secret in
`dev-release-team-tenant` before or when you create the Component. Name:
`pipelines-as-code-secret-img-pool-{component}`. Point `spec.secret` on the
Component at that name. If a Component exists without `spec.secret`, delete it
(remove finalizers if needed) and recreate with `secret` set.

Example for `ls-v4-15-apiserver-watcher-01` (replace name, annotation, and PAT):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: pipelines-as-code-secret-img-pool-ls-v4-15-apiserver-watcher-01
  namespace: dev-release-team-tenant
  labels:
    appstudio.redhat.com/credentials: scm
    appstudio.redhat.com/scm.host: github.com
  annotations:
    appstudio.redhat.com/scm.repository: hacbs-release-tests/img-pool-ls-v4-15-apiserver-watcher-01
type: kubernetes.io/basic-auth
stringData:
  password: "<your-github-pat>"
```

Apply with `kubectl apply -f` (or create the equivalent Secret in the UI).

**Step 4 — Create the Component and finish PAC setup**

1. Create a **Component** in the correct Application: git URL, component branch,
   `spec.secret: pipelines-as-code-secret-img-pool-{component}`, and the
   `docker-build-oci-ta` build pipeline annotation.
2. Wait until PAC is **enabled** on the Component.
3. On GitHub, open PAC’s configuration PR: keep push-only / single-arch / buildah
   pin as in step 1, merge the PR.
4. If PAC stalls (“no history in common”), delete stray `konflux-*` branches, then
   annotate `build.appstudio.openshift.io/request=configure-pac` on the Component.

**Step 5 — Trigger the build and verify Quay**

1. Push a commit to the component branch if the merge did not already trigger a build.
2. In Konflux or `kubectl`, wait until the on-push **PipelineRun** status is
   **Succeeded**.
3. In Quay, open `redhat-user-workloads-stage/dev-release-team-tenant/{component}`:
   confirm tag **`stable`**, Tekton Chains signature tags (`sha256-….sig`), and that
   the image matches what you expect.
4. Optionally patch `status.lastPromotedImage` on the Component for easier debugging
   in the UI.

**Step 6 — Manually add one line to the pool file**

Edit [`static-image-pool-stable.txt`](resources/static-image-pool-stable.txt) and
manually add exactly one line, e.g.
`quay.io/redhat-user-workloads-stage/dev-release-team-tenant/ls-v4-15-apiserver-watcher-01:stable`.
Repeat steps 1–6 until the file has **200** lines (sorted by version, then name).

## When something is missing or broken

If a step fails, check the component against this table before you add or keep a
pool line.

| What you see | What to do |
|---|---|
| **GitHub repo does not exist** | Create `hacbs-release-tests/img-pool-{component}` (replace `{component}` with the full Konflux name, e.g. `ls-v4-15-apiserver-watcher-01`). Push the template Dockerfile and `.tekton/` on the component branch. |
| **Repo exists but PAC cannot clone / Error 70** | Apply the SCM secret above; verify PAT with `curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/hacbs-release-tests/img-pool-{component}`. |
| **Application missing** | `kubectl get application large-snapshot-build-v4-15 -n dev-release-team-tenant` (and siblings for 4.16–4.21). Apply an Application manifest if missing (see naming section). |
| **Component missing** | Create the Component CR linked to the git repo, branch, Application, build pipeline annotation, and SCM secret above. |
| **PAC not enabled** | Wait; if stuck, annotate `build.appstudio.openshift.io/request=configure-pac` on the Component. Fix SCM secret / repo access first. |
| **PAC PR conflicts or “no history in common”** | On GitHub: resolve or close the bad PR, delete stray `konflux-*` branches, re-request `configure-pac`. |
| **No successful build / PipelineRun failed** | Read the failed TaskRun logs (buildah, git clone, EC policy). Fix Dockerfile or `.tekton/` (buildah 0.7 pin on stage, single-arch platforms, push-only). Re-push the component branch. |
| **Build succeeded but no `:stable` in Quay** | Confirm `LABEL konflux.additional-tags="stable"` in the Dockerfile and that the push pipeline completed. Check Quay repo `redhat-user-workloads-stage/dev-release-team-tenant/{component}`. |
| **Quay has image but Component `lastPromotedImage` empty** | Patch status if you need the UI to show the digest, e.g. `kubectl patch component {name} -n dev-release-team-tenant --subresource=status --type=merge -p '{"status":{"lastPromotedImage":"quay.io/...@{digest}"}}'`. Pool file can still use `:stable` if the tag exists. |
| **Image gone from Quay but Component still exists (“zombie”)** | Treat as missing: rebuild (push repo) or delete Component and start again. Remove the old line from `static-image-pool-stable.txt` until a new image is verified. |
| **No Tekton Chains `.sig` on Quay** | Wait for Chains; if never appears, check namespace Chains config and rerun the build. rh-advisories expects signed images. |
| **Token cannot access repo** | Verify PAT: `curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/hacbs-release-tests/img-pool-{component}` returns 200. Renew token, fix org SSO authorization, or use a cluster secret such as `hacbs-release-tests-token` if your team stores PATs there. |
| **Cannot inspect private Quay repos** | Optional namespace secret `test-quay-token-secret` (`.dockerconfigjson` for `quay.io`) — same pattern as other release integration tests — for API/skopeo checks; not required if tags are visible in the Quay UI. |

Only after the row for your component is green add its line to
`static-image-pool-stable.txt`. Document unusual fixes in the PR or team channel so
the next person knows what was wrong.

## Incremental refresh

1. In Quay and the Konflux UI (or `kubectl`), check which pool components still have
   a valid `:stable` image.
2. Leave unchanged lines in `static-image-pool-stable.txt` for images that still work.
3. For each missing slot, repeat **steps 1–6** above and manually add one line until
   the file has 200 lines again.
4. When adding several components in a row, pause between builds so stage PAC and
   GitHub are not flooded.

## Validating before commit

1. Exactly **200** non-empty lines (the test checks this).
2. Each reference resolves in Quay.
3. The image path segment matches the Konflux component name expected by
   `generate-large-snapshot.sh`.
4. Dry-run with `FRESH_BUILDS_FILE` pointing at the draft list.

## Greenfield regeneration

Use only when intentionally replacing the entire pool (new prefix, architecture
change, etc.). Follow steps 1–6 for each component and manually add each Quay
reference to `static-image-pool-stable.txt` as builds complete. When all 200 lines are
present and reviewed, run `/test-large-snapshot` once on stage before merging the file.

Expect many hours for 200 single-arch builds; multi-arch multiplies build and
signing time.

## Optional cleanup

Resources are often left in place for reuse. To reclaim them:

- `kubectl delete application large-snapshot-build-v4-… -n dev-release-team-tenant`
- Delete `img-pool-*` GitHub repos and Quay repos only when nothing else depends on them.