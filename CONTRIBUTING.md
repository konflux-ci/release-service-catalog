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

<<<<<<< HEAD
=======

>>>>>>> 2deac63 (docs(HACBS-667): update repository documents)
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

<<<<<<< HEAD
```
feat(issue-id): what this commit does

Overall explanation of what this commit is achieving and the motivation behind it.

=======
 ```
feat(issue-id): what this commit does

Overall explanation of what this commit is achieving and the motivation behind it.
<<<<<<< HEAD
 
>>>>>>> 2deac63 (docs(HACBS-667): update repository documents)
=======

>>>>>>> 059e3fd (feat(HACBS-2184): enable tekton task testing for apply-mapping)
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
<<<<<<< HEAD
<<<<<<< HEAD

## Testing

Tests are written using the *[Ginkgo](https://onsi.github.io/ginkgo/)* framework. Here are some general advices when writing tests:

* When the global `Describe` doesn't add enough context to the tests, use a nested `Describe` or a `Context` to specify what this test alludes to. Contexts should always start with _When_ (ie. "_When calling the function Foo_")
* Start the descriptions of `It` blocks in lowercase and try to be as descriptive as possible
* Avoid ignoring errors. In other words, make sure all of them are caught and tested
* Files ending with `_suite_test.go` are meant to store the code that is common for tests in the same directory and that will be executed before them. Use these files only if your test setup is big enough to justify it (ie. the suite file has more than the test suite name and the teardown)
* When required, remember to add the `CRD`'s during the `envtest` setup, for instance: [release-service/release_suite_test.go at main · redhat-appstudio/release-service · GitHub](https://github.com/redhat-appstudio/release-service/blob/main/controllers/release/release_suite_test.go#L65) - remembering this saves a lot of time
* After `Create()` or `Update()` objects, use `Get()` before making assurances as the object might be outdated. It is useful after `Delete()` to check if the client returns `errors.IsNotFound`
* Some assurances are likely to require usage of `Eventually` blocks instead of or in addition to `Expect` blocks

### Useful links:

Links that may be used as a starting point:

* [Getting started with Ginkgo](https://onsi.github.io/ginkgo/#getting-started)
* [Gomega reference doc](https://pkg.go.dev/github.com/onsi/gomega#section-readme)
* [Writing controller tests](https://book.kubebuilder.io/cronjob-tutorial/writing-tests.html)
* [Testing your Operator project](https://master.sdk.operatorframework.io/docs/building-operators/golang/testing/)

Unofficial (but useful) links:

* [Ginkgo and Gomega gotchas](https://medium.com/@william.la.martin/ginkgotchas-yeh-also-gomega-13e39185ec96)
* [Effective Ginkgo/Gomega](https://medium.com/swlh/effective-ginkgo-gomega-b6c28d476a09)
=======
>>>>>>> 2deac63 (docs(HACBS-667): update repository documents)
=======

### Tekton Task Testing

When a pull request is opened, Tekton Task tests are run for all the task version
directories that are modified.

The Github workflow is defined in
[.github/workflows/tekton_task_tests.yaml](.github/workflows/tekton_task_tests.yaml)

#### Adding new Tekton Task tests

Tests are defined as Tekton Pipelines inside the `tests` subdirectory of the task version
directory. Their filenames must match `test*.yaml` and the Pipeline name must be
the same as the filename (sans `.yaml`).

E.g. to add a test pipeline for `catalog/task/apply-mapping/0.3`, you can add a pipeline
such as `catalog/task/apply-mapping/0.3/tests/test-apply-mapping.yaml`.

To reference the task under test in a test pipeline, use just the name - the test
script will install the task CR locally. For example:

```
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

```
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
./.github/scripts/test_tekton_tasks.sh catalog/task/apply-mapping/0.3
```

This will install the task and run all test pipelines matching `tests/test*.yaml`.
>>>>>>> 059e3fd (feat(HACBS-2184): enable tekton task testing for apply-mapping)
