# Contributing

Contributions of all kinds are welcome. In particular pull requests are appreciated. The authors and maintainers will endeavor to help walk you through any issues in the pull request discussion, so please feel free to open a pull request even if you are new to such things.

## Code of Conduct

Our [company values](https://www.redhat.com/en/about/brand/standards/culture) guide us in our day-to-day interactions and decision-making. Our open source projects are no exception and they will define the standards for how to engage with the project through a [code of conduct](CODE_OF_CONDUCT.md).

Please, make sure you read both of them before contributing, so you can help us to maintain a healthy community.

## Requesting support

Before you ask a question, it is best to search for existing Issues that might help you. In case you have found a suitable issue and still need clarification, you can write your question in this issue. It is also advisable to search the internet for answers first.

If you then still feel the need to ask a question and need clarification, we recommend the following:

* Open an [Issue](/issues/new).
* Provide as much context as you can about what you’re running into.
* Provide project and platform versions (golang, operator-sdk, etc), depending on what seems relevant.
* The community will then take care of the issue as soon as possible.

## Reporting Bugs

We use GitHub issues to track bugs and errors. If you run into an issue with the project:

* Open an [Issue](/issues/new).
* Explain the behavior you would expect and the actual behavior.
* Please provide as much context as possible and describe the reproduction steps that someone else can follow to recreate the issue on their own. This usually includes your code. For good bug reports you should isolate the problem and create a reduced test case.

Once it’s filed:

* The project team will label the issue accordingly.
* A team member will try to reproduce the issue with your provided steps. If there are no reproduction steps or no obvious way to reproduce the issue, the team will ask you for those steps and mark the issue as `needs-reproducer`. Bugs with this tag will not be addressed until they are reproduced.
* If the team is able to reproduce the issue, it will be marked `needs-fix` and left to be implemented by someone. Other labels can be used in addition to better describe the issue or its criticality.


## Requesting a feature

Enhancement suggestions are tracked as [GitHub issues](/issues).

- Use a **clear and descriptive title** for the issue to identify the suggestion.
- Provide a **step-by-step description of the suggested enhancement** in as many details as possible.
- Describe the current behavior, the expected one, and why you expect this behavior. At this point you can also list which alternatives do not work for you.
- **Explain why this enhancement would be useful** to other users. You may also want to point out the other projects that solved it better and could serve as inspiration.

## Submitting changes

Before contributing code or documentation to this project, make sure you read the following sections.

### Commit message formatting and standards

The project follows the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification and enforces it using [gitlint](https://jorisroovers.com/gitlint/). The rules for this project are specified in the [.gitlint](.gitlint) config file. There is also a second rule file for the commit description that can be found in the [.github/gitlint directory](.github/gitlint).

The commit message should contain an overall explanation about the change and the motivation behind it. Please note that mentioning a Jira ticket ID or a GitHub issue, isn't a replacement for that.

A well formatted commit would look something like this:

 ```
feat(issue-id): what this commit does

Overall explanation of what this commit is achieving and the motivation behind it.

Signed-off-by: Your Name <your-name@your-email.com>
```

### Signing commits

This project also enforces GPG signed commits. More information on commit signing and how to do it can be found in the [git official docs](
https://git-scm.com/book/en/v2/Git-Tools-Signing-Your-Work) or in [this GitHub guide](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits). You can see whether or not the commit was successfully signed by the `Verified` bubble next to your commit in the GitHub UI or using `git log`.

### Pull Requests

All changes must come from a pull request (PR) and cannot be directly committed. While anyone can engage in activity on a PR, pull requests are only approved by team members.

Before a pull request can be merged:

* The content of the PR has to be relevant to the PR itself
* The contribution must follow the style guidelines of this project
* Multiple commits should be used if the PR is complex and clarity can be improved, but they should still relate to a single topic
* For code contributions, tests have to be added/modified to ensure the code works
* There has to be at least one approval
* The feature branch must be rebased so it contains the latest changes from the target branch
* The CI has to pass successfully
* Every comment has to be addressed and resolved

### Image References

Most tasks in this repo use the release-service-utils image defined in [the release-service-utils repo](https://github.com/redhat-appstudio/release-service-utils).
When referencing this image, the url should be `quay.io/redhat-appstudio/release-service-utils:$tag` where `$tag` is the Git SHA based tag.

For other images, the reference should always either specify an image by a non-moving tag (e.g. `registry.access.redhat.com/ubi8/ubi:8.8-1067.1698056881`)
or by its digest (e.g. `registry.access.redhat.com/ubi8/ubi@sha256:c94bc309b197f9fc465052123ead92bf50799ba72055bd040477ded`).
Floating tags like `latest` or `8.8` in the case of the ubi image should be avoided.

### Tekton Task Testing

When a pull request is opened, Tekton Task tests are run for all the task directories
that are being modified.

The Github workflow is defined in
[.github/workflows/tekton_task_tests.yaml](.github/workflows/tekton_task_tests.yaml)

#### Adding new Tekton Task tests

Tests are defined as Tekton Pipelines inside the `tests` subdirectory of the task
directory. Their filenames must match `test*.yaml` and the Pipeline name must be
the same as the filename (sans `.yaml`).

E.g. to add a test pipeline for `tasks/apply-mapping`, you can add a pipeline
such as `tasks/apply-mapping/tests/test-apply-mapping.yaml`.

To reference the task under test in a test pipeline, use just the name - the test
script will install the task CR locally. For example:

```yaml
- name: run-task
    taskRef:
      name: apply-mapping
```

Currently task tests are not required, so if a task version directory is modified
in a PR and there are no tests, that directory will be skipped.

##### Testing scenarios where the Task is expected to fail

When testing Tasks, most tests will test a positive outcome - that for some input, the task will pass
and provide the correct output. But sometimes it's desirable to test that a Task fails when
it's expected to fail, for example when invalid data is supplied as input for the Task.
But if the Task under test fails in the test Pipeline, the whole Pipeline will fail too. So we need
a way to tell the test script that the given test Pipeline is expected to fail.

You can do this by adding the annotation `test/assert-task-failure`
to the test pipeline object. This annotation will specify which task (`.spec.tasks[*].name`)
in the pipeline is expected to fail. For example:

```yaml
---
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: test-apply-mapping-fail-on-empty
  annotations:
    test/assert-task-failure: "run-task"
```

When this annotation is present, the test script will test that the pipeline fails
and also that it fails in the expected task.

##### Workspaces

Some tasks require one or multiple workspaces. This means that the test pipeline will also
have to declare a workspace and bind it to the workspace(s) required by the task under test.

Currently, the test script will pass a single workspace named `tests-workspace` mapping
to a 10Mi volume when starting the pipelinerun. This workspace can be used in the test pipeline.

##### Test Setup

Some task tests will require setup on the kind cluster before the test pipeline can run.
Certain things can be done in a setup task as part of the test pipeline, but others cannot.
For example, something like installing a CRD or modifying permissions for the service account that will
execute the test pipeline must be done before the test pipeline is executed.

In order to achieve this, a `pre-apply-task-hook.sh` script can be created in the `tests` directory for
a task. When the CI runs the testing, it will first check for this file. If it is found, it is executed
before the test pipeline. This script will run as the `kubeadmin` user. This approach is copied from the
tekton catalog repository. For more details and examples, look
[here](https://github.com/tektoncd/catalog/blob/main/CONTRIBUTING.md#end-to-end-testing).

##### Mocking commands executed in task scripts

Mocks are needed when we want to test tasks which call external services (e.g. `scopeo copy`,
`cosign download`, or even a python script from our release-utils image such as `create_container_image` that would
call Pyxis API). The way to do this is to create a file with mock shell functions (with the same names
as the commands you want to mock) and inject this file to the beginning of each `script` field in
the task step that needs mocking.

For reference implementation, check [create-pyxis-image/tests/](tasks/create-pyxis-image/tests/). Here's a breakdown of how it's done:

1. Create a `mocks.sh` file in the tests directory of your task, e.g.
    `tasks/create-pyxis-image/tests/mocks.sh`. This file will contain the mock function
    definitions. It also needs to contain a shebang at the top as it will get injected to the top
    of the original script. For example:

    ```sh
    #!/usr/bin/env sh
    set -eux

    function cosign() {
      echo Mock cosign called with: $*
      echo $* >> $(workspaces.data.path)/mock_cosign.txt

      if [[ "$*" != "download sbom --output-file myImageID"[12]".json imageurl"[12] ]]
      then
        echo Error: Unexpected call
        exit 1
      fi

      touch /workdir/sboms/${4}
    }
    ```

    In the example above, you can notice two things:
    - Each time the mock function is called, the full argument list is saved in a file in the
      workspace. This is optional and depends on your task's workspace name. It allows us to
      check mock calls after task execution in our test pipeline.
    - In this case the function touches a file that would otherwise be created by the actual `cosign`
      call. This is specific to the task and will depend on your use case.
    - Note: In the example above, the function being mocked is `cosign`. If that function was actually something
      that had a hyphen in its name (e.g. `my-cool-function`), the tests would fail with
      `my-cool-function: not a valid identifier` messages. This is because when you use `#!/usr/bin/env sh`, Bash
      runs in POSIX mode in which case hyphens are not permitted in function names. The solution to this is to use
      `#!/bin/bash` or `#!/usr/bin/env bash` in place of `#!/usr/bin/env sh` at the top of the file. Keep in mind
      that the same shell declaration should be used in both the mock and the tekton task step script you are
      mocking to ensure the behavior during test is the same as during runtime.

1. In your `pre-apply-task-hook.sh` file (see the Test Setup section above for explanation), include
    `yq` commands to inject the `mocks.sh` file to the top of your task step scripts, e.g.:

    ```sh
    #!/usr/bin/env sh

    TASK_PATH=$1
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

    yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[0].script' $TASK_PATH
    yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' $TASK_PATH
    ```

    In this case we inject the file to both steps in the task under test. This will depend on
    the given task. You only need to inject mocks for the steps where something needs to be mocked.

1. (Optional) In your test pipeline, you can have a task after the main task under test that will
    check that the mock functions had the expected calls. This only applies if you saved your mock
    calls to a file. In our example, it will look something like this:

    ```sh
    if [ $(cat $(workspaces.data.path)/mock_cosign.txt | wc -l) != 2 ]; then
      echo Error: cosign was expected to be called 2 times. Actual calls:
      cat $(workspaces.data.path)/mock_cosign.txt
      exit 1
    fi
    ```

Note: The approach described above shows the recommended approach. But there may be variations
depending on your needs. For example, you could have several mocks files and inject different
files to different steps in your task.

#### Running Tekton Task tests manually

Requirements:

* A k8s cluster running and kubectl default context pointing to it (e.g. [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation))
* Tekton installed in the cluster ([docs](https://tekton.dev/docs/pipelines/install/))

    ```kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml```

* tkn cli installed ([docs](https://tekton.dev/docs/cli/))

* jq installed

Once you have everything ready, you can run the test script and pass task version directories
as arguments, e.g.

```
./.github/scripts/test_tekton_tasks.sh tasks/apply-mapping
```

This will install the task and run all test pipelines matching `tests/test*.yaml`.

Another option is to run one or more tests directly:

```
./.github/scripts/test_tekton_tasks.sh tasks/apply-mapping/tests/test-apply-mapping.yaml
```

This will still install the task and run `pre-apply-task-hook.sh` if present, but it will then
run only the specified test pipeline.

### Openshift CI Prow Tests

Each PR runs the [release-pipelines e2e test suite](https://github.com/redhat-appstudio/e2e-tests/tree/main/tests/release/pipelines).
This is to ensure that a change does not break any pipeline functionality, as the tekton unit tests only test the tasks.
This shows up as the `ci/prow/release-pipelines-e2e-suite` check on the PR.

#### Pairing with E2E Change

Sometimes, a change to a pipeline definition will require a change to the e2e test in order to pass. To do this, the changes should be paired.

Process:
  This is described in depth [here](https://github.com/redhat-appstudio/e2e-tests/blob/main/docs/Installation.md#rhtap-in-openshift-ci-and-branch-pairing).
  The short explanation for it is that you should open a PR that makes the necessary changes to the test suite in
  [the e2e repo](https://github.com/redhat-appstudio/e2e-tests) using the same branch name as your PR to this repository. This will pair them. Once the
  PR to this repo is merged, the e2e-tests PR should also be merged so that future PRs to this repo will pass (as they will now be dependent on the e2e change).

#### Pairing with release-service Change

Another possible pairing scenario is a change to a pipeline definition that requires changes to the operator itself, stored in
[the release-service repo](https://github.com/redhat-appstudio/release-service). For example, maybe a parameter is passed by the operator
to the pipeline, and the name of the parameter is changing. This will require the release-service PR and release-service-catalog PR to be paired
in order for the e2e suite to pass.
Note: This can be used in conjunction with the e2e pairing described in the previous section. That is to say, you can also pair an e2e-tests
PR with these two PRs.

Process:
* Open a PR to the [release-service](https://github.com/redhat-appstudio/release-service). This PR should usually be opened as a draft. In order to run the
required check that builds the image for your catalog PR CI run, comment `/test images` on the PR. This will trigger the `ci/prow/images` check on the
release-service PR. So, it is important to open the release-service PR first and wait for that check to succeed.
* Open a PR to this repo. Use the same branch name as you did in the release-service PR (just like you do to pair with e2e-tests PRs). The e2e test suite
for your catalog PR will deploy a cluster using your release-service image built as part of your release-service PR checks. It will then run the test suite
with the `RELEASE_SERVICE_CATALOG_URL` and `RELEASE_SERVICE_CATALOG_REVISION` environment variables set to point all ReleasePlanAdmissions in the e2e suite
to your catalog PR. As a result, the test suite will run with your changes.
* Once the catalog CI run completes and the code review process is complete, the catalog PR should be merged. This should happen before the release-service
PR is merged. At that point, you will be working with an unpaired release-service PR, or if this change also included an e2e change, a release-service
PR paired with an e2e change (documented [here](https://github.com/redhat-appstudio/e2e-tests/blob/main/docs/Installation.md#rhtap-in-openshift-ci-and-branch-pairing)),
but the catalog PR pairing process will be complete.
* Pairing is typically only required for breaking changes, so once the catalog PR is merged, things are now in a broken state. This should be resolved ASAP by
marking the release-service PR as ready, merging it, and promoting its results to the infra-deployments overlays.
