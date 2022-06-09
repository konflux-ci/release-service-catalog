# release-bundles

This repo stores Tekton bundle definition (yaml) sources for the HACBS release-service.



## Tekton bundles
Tekton Bundles are a collection of Pipelines & Tasks stored within container images.

Conceptually a bundle may resemble something like the following diagram:
---
```mermaid
    flowchart TB
    subgraph bundle [Tekton Bundle]
        subgraph pipeline1["Pipeline 1"]
            direction LR
            subgraph task1["Task 1"]
                subgraph steps1[" "]
                    step1[step 1]-->step2[step 2]
                    step2[step 2]-->step3[step 3]
                end
            end
            subgraph task2["Task 2"]
                subgraph steps2[" "]
                    stepa[step 1]-->stepb[step 2]
                    stepb[step 2]-->stepc[step 3]
                end
            end
            subgraph task3["Task 3"]

                subgraph steps3[" "]
                    stepI[step 1]-->stepII[step 2]
                    stepII[step 2]-->stepIII[step 3]
                end
            end
            task1 --> task2
            task2 --> task3
        end
    end
```

Each Tekton Pipeline or Task CDR definition is stored as a layer in the container image.

```mermaid
    flowchart TB
    subgraph container["Container"]
        direction TB
        pl1["Pipeline 1</br>(Layer 1)"]---ta1["Task 1</br>(Layer 2)"]
        ta1["Task 1</br>(Layer 2)"]---ta3["Task 2</br>(Layer 3)"]
    end

```


---

### Creating Tekton Bundles in release-bundles repo
* Creating a Teton bundle is as easy as creating a new directory under `definitions/[BUNDLE_NAME]` directory.
* The name of the directory becomes the name of the Tekton bundle from the image registry perspective.
* YAML definitions for Pilelines & Task can be kept in a single file, delineated by `---` document-start, and optionally `...` document-end symbols.
* Or alternatively, YAML definitions can be kepts in separate files; the CI will merge them all into the bundle. This way discrete tasks used within a pipeline could be reused like building-blocks. For example, a task to clone a git repository could be used in multiple pipelines within a bundle.
* Generated bundles will be tagged with the git sha-1 commit from main branch, and also tagged with "main" attributing the branch the commit was merged into.
* YAML linting is used to ensure all bundle definitions conform to a set of style standards enforced by CI. Please review the config file `.yamllint` for more details, and review [upstream documentation](https://yamllint.readthedocs.io/en/stable/). If the need occurs rules could be disabled perline within the YAML file, for example suppressing long-line errors where line-breaks are not feasible.


---

### The workflow resembles the following graph
```mermaid
    flowchart LR
    subgraph github["GitHub - release-bundles"]
        subgraph bundle["./definitions/FOO/"]
            direction LR
            a["pipeline-1.yaml"]---b["task-1.yaml"]
            a["pipeline-1.yaml"].--c["task-2.yaml"]
            a["pipeline-1.yaml"].--d["task-3.yaml"]

            x["pipeline-2.yaml"].--c["task-2.yaml"]
            x["pipeline-2.yaml"].--d["task-3.yaml"]
            x["pipeline-2.yaml"]---e["task-4.yaml"]
            x["pipeline-2.yaml"]---f["task-5.yaml"]
        end
    end
    subgraph quay["Quay.io"]
        subgraph ns["Org Namespace"]
            subgraph imgrepo["Repo: FOO"]

                y1["FOO:latest"] --> y2["FOO:digest"]
                y1["FOO:latest"] --> y3["FOO:tag"]
                y3["FOO:tag"] --> y2["FOO:digest"]
            end
        end
    end
    github --"push"----> quay
```
