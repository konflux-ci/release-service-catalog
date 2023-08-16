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
 
>>>>>>> 2deac63 (docs(HACBS-667): update repository documents)
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
