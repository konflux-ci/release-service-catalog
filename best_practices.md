
<b>Pattern 1: When changing task behavior or adding non-obvious constraints, update the PR description/commit message and in-repo documentation to clearly explain the rationale, scope, and any surprising semantics (e.g., idempotency being handled downstream, or a security requirement enforced by CI).
</b>

Example code before:
```
# Code change introduces new behavior/constraint, but no accompanying docs.
# (e.g., task now re-processes artifacts on reruns; or requires non-root user)
```

Example code after:
```
# README / PR description explains implications and reason:
# - Reruns will reprocess all artifacts; downstream tool dedupes.
# - Tasks using Trusted Artifacts must run as UID 1001 (CI-enforced).
## Important Note on Behavior
# ...explanation...
```

<details><summary>Examples for relevant past discussions:</summary>

- https://github.com/konflux-ci/release-service-catalog/pull/1754#discussion_r2686853790
- https://github.com/konflux-ci/release-service-catalog/pull/1524#discussion_r2447127817
- https://github.com/konflux-ci/release-service-catalog/pull/1638#discussion_r2564410279
</details>


___

<b>Pattern 2: In Tekton bash scripts, prefer explicit, named parameters and environment variables over magic numbers and unclear identifiers, and align names with how they are consumed (including case) to avoid confusion and Shellcheck false positives.
</b>

Example code before:
```
# Magic constant and unclear var naming
WARN_DAYS="7"
requester="$(params.requester)"
if [[ "$PYXIS_SERVER" == "production-internal" ]]; then
  ...
fi
```

Example code after:
```
# Named param with explicit meaning + consistent env naming
CERT_EXPIRATION_WARN_DAYS="$(params.certExpirationWarnDays)"
REQUESTER="$(params.requester)"
if [[ "$(params.pyxisServer)" == "production" ]]; then
  # production here maps to internal production due to cluster egress limits
  ...
fi
```

<details><summary>Examples for relevant past discussions:</summary>

- https://github.com/konflux-ci/release-service-catalog/pull/1709#discussion_r2592304995
- https://github.com/konflux-ci/release-service-catalog/pull/1638#discussion_r2576249580
- https://github.com/konflux-ci/release-service-catalog/pull/1638#discussion_r2564410279
</details>


___

<b>Pattern 3: For tasks that use remote hosts or shared infrastructure (SSH/scp, remote temp directories), ensure isolation and traceability by scoping remote work to a unique per-run identifier (prefer Tekton TaskRun/pipeline identifiers) and performing explicit cleanup after success/failure.
</b>

Example code before:
```
# Shared remote path can collide across runs
ssh "$HOST" "rm -rf ~/kmods && mkdir -p ~/kmods"
scp *.ko "$HOST:~/kmods/"
ssh "$HOST" "sign ~/kmods/*.ko"
```

Example code after:
```
# Isolated per TaskRun, traceable, and cleaned up
TASK_UID="$(context.taskRun.uid)"
ssh "$HOST" "mkdir -p ~/${TASK_UID}/kmods"
scp *.ko "$HOST:~/${TASK_UID}/kmods/"
ssh "$HOST" "sign ~/${TASK_UID}/kmods/*.ko"
ssh "$HOST" "rm -rf ~/${TASK_UID}"
```

<details><summary>Examples for relevant past discussions:</summary>

- https://github.com/konflux-ci/release-service-catalog/pull/1750#discussion_r2611528949
- https://github.com/konflux-ci/release-service-catalog/pull/1750#discussion_r2611495032
</details>


___

<b>Pattern 4: In bash-heavy tasks and test harnesses, reduce duplication and improve robustness by extracting repeated logic into helper functions and by avoiding mechanisms that bloat generated scripts/arguments (e.g., prefer sourcing mounted mocks via ConfigMap over prepending large mock blocks).
</b>

Example code before:
```
# Repeated copy-back/sign/checksum logic in multiple branches,
# plus large inline mocks concatenated into each step.
for step in steps; do
  step.script = load_str("mocks.sh") + step.script
done
# ...duplicated scp/ssh/copy-back blocks...
```

Example code after:
```
# Mount mocks and source them; centralize repeated operations
kubectl create configmap test-mocks --from-file=mocks.sh=./mocks.sh
# task steps: source /mnt/test-mocks/mocks.sh
copy_signed_kmods_back() { ... }
sign_single_arch_workflow() { ... }
```

<details><summary>Examples for relevant past discussions:</summary>

- https://github.com/konflux-ci/release-service-catalog/pull/1750#discussion_r2614777820
- https://github.com/konflux-ci/release-service-catalog/pull/1692#discussion_r2592597556
- https://github.com/konflux-ci/release-service-catalog/pull/1692#discussion_r2592602858
</details>


___
