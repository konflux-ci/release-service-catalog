#!/usr/bin/env python3
"""Warn when Tekton step or pipeline-task names change.

RPA taskRunSpecs.stepSpecs in konflux-release-data match the current
Tekton step name and pipeline task name. A stale name is a silent no-op.
This script posts an inline review comment; it does not fail CI.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from typing import Any

import yaml

MARKER = "rpa-step-rename-check"
KRD_URL = "https://gitlab.cee.redhat.com/releng/konflux-release-data"
DOCS = (
    "https://github.com/konflux-ci/release-service-catalog/blob/development/"
    "CONTRIBUTING.md#adding-new-tasks"
)
INTERESTING_PREFIXES = ("tasks/", "pipelines/")
SKIP_SUBSTRINGS = ("/tests/", "integration-tests/")


def git_output(*args: str) -> str:
    return subprocess.check_output(["git", *args], text=True)


def load_yaml(text: str) -> dict[str, Any] | None:
    if not text.strip():
        return None
    docs = [doc for doc in yaml.safe_load_all(text) if doc]
    return docs[0] if docs else None


def names_from_doc(doc: dict[str, Any] | None) -> set[str]:
    if not doc or not isinstance(doc, dict):
        return set()
    kind = str(doc.get("kind") or "")
    spec = doc.get("spec") or {}
    names: set[str] = set()
    if kind == "Task":
        for step in spec.get("steps") or []:
            name = (step or {}).get("name")
            if name:
                names.add(str(name))
    elif kind == "Pipeline":
        for task in (spec.get("tasks") or []) + (spec.get("finally") or []):
            name = (task or {}).get("name")
            if name:
                names.add(str(name))
    return names


def show_file(sha: str, path: str) -> str | None:
    try:
        return git_output("show", f"{sha}:{path}")
    except subprocess.CalledProcessError:
        return None


def find_name_line(text: str, name: str) -> int | None:
    pattern = re.compile(rf"^\s*- name:\s*{re.escape(name)}\s*$")
    for i, line in enumerate(text.splitlines(), 1):
        if pattern.match(line):
            return i
    return None


def api_request(method: str, url: str, token: str, payload: dict | None = None) -> Any:
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as exc:
        err = exc.read().decode()
        raise RuntimeError(f"GitHub API {method} {url} failed: {exc.code} {err}") from exc


def comment_body(path: str, kind_label: str, removed: list[str], added: list[str]) -> str:
    removed_fmt = ", ".join(f"`{n}`" for n in removed)
    added_fmt = ", ".join(f"`{n}`" for n in added) if added else "_(none — name removed)_"
    return f"""<!-- {MARKER}:{path}:{','.join(removed)} -->
**RPA override check** — please resolve this conversation after you have looked.

This PR changes {kind_label} name(s) in `{path}`:
- **Removed / old:** {removed_fmt}
- **Added / new:** {added_fmt}

ReleasePlanAdmission `taskRunSpecs` in [konflux-release-data]({KRD_URL}) match the **current** pipeline task name (`pipelineTaskName`) and step name (`stepSpecs.name`). A stale name is a silent no-op, so memory or timeout overrides never apply.

Please:
1. Search KRD for the **old** name(s) under `taskRunSpecs` / `stepSpecs`
2. Coordinate an RPA update if anything still uses them
3. **Resolve this conversation** after you have checked (even if unused)

Docs: [CONTRIBUTING.md — Adding New Tasks]({DOCS})
"""


def main() -> int:
    token = os.environ["GITHUB_TOKEN"]
    repo = os.environ["GITHUB_REPOSITORY"]
    pr_number = os.environ["PR_NUMBER"]
    base_sha = os.environ["BASE_SHA"]
    head_sha = os.environ["HEAD_SHA"]

    changed = git_output("diff", "--name-only", base_sha, head_sha).splitlines()
    findings: list[dict[str, Any]] = []
    for path in changed:
        if not path.endswith((".yaml", ".yml")):
            continue
        if not path.startswith(INTERESTING_PREFIXES):
            continue
        if any(skip in path for skip in SKIP_SUBSTRINGS):
            continue

        old_text = show_file(base_sha, path)
        new_text = show_file(head_sha, path)
        if old_text is None:
            continue  # new file — nothing for existing RPAs to already reference
        old_names = names_from_doc(load_yaml(old_text))
        new_names = names_from_doc(load_yaml(new_text or ""))
        removed = sorted(old_names - new_names)
        if not removed:
            continue
        added = sorted(new_names - old_names)
        kind_label = "step" if path.startswith("tasks/") else "pipeline task"
        line = None
        if new_text and added:
            line = find_name_line(new_text, added[0])
        findings.append(
            {
                "path": path,
                "removed": removed,
                "added": added,
                "line": line,
                "kind_label": kind_label,
            }
        )

    if not findings:
        print("No Task step or Pipeline task name removals/renames detected.")
        return 0

    print("Findings:")
    print(json.dumps(findings, indent=2))

    existing = api_request(
        "GET",
        f"https://api.github.com/repos/{repo}/pulls/{pr_number}/comments?per_page=100",
        token,
    )
    existing_markers = {
        m.group(0)
        for comment in existing
        for m in [re.search(rf"<!-- {MARKER}:.*? -->", comment.get("body") or "")]
        if m
    }

    review_comments = []
    leftover = []
    for finding in findings:
        marker = f"<!-- {MARKER}:{finding['path']}:{','.join(finding['removed'])} -->"
        if any(marker in body for body in existing_markers) or marker in existing_markers:
            print(f"Skipping already-commented finding for {finding['path']}")
            continue
        body = comment_body(
            finding["path"], finding["kind_label"], finding["removed"], finding["added"]
        )
        if finding["line"] is not None:
            review_comments.append(
                {
                    "path": finding["path"],
                    "line": finding["line"],
                    "side": "RIGHT",
                    "body": body,
                }
            )
        else:
            leftover.append(body)

    api_root = f"https://api.github.com/repos/{repo}"
    if review_comments:
        try:
            api_request(
                "POST",
                f"{api_root}/pulls/{pr_number}/reviews",
                token,
                {
                    "commit_id": head_sha,
                    "event": "COMMENT",
                    "body": (
                        "Step or pipeline-task names changed. Please search "
                        f"[konflux-release-data]({KRD_URL}) for matching RPA "
                        "`taskRunSpecs` and resolve the inline comment(s) after checking."
                    ),
                    "comments": review_comments,
                },
            )
            print(f"Posted {len(review_comments)} inline review comment(s).")
        except RuntimeError as exc:
            print(f"Inline review comment failed, falling back to PR comment: {exc}")
            leftover.extend(c["body"] for c in review_comments)

    for body in leftover:
        api_request(
            "POST",
            f"{api_root}/issues/{pr_number}/comments",
            token,
            {"body": body},
        )
        print("Posted a PR-level fallback comment.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
