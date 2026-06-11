#!/usr/bin/env python3
"""Integration tests for the create-pr step functions.

Hits real GitHub and Quay APIs — no mocking.
Run locally: python3 test_create_pr.py
"""

import re
import sys

import requests

GITHUB_API_URL = "https://api.github.com"


# ---------------------------------------------------------------------------
# Functions under test (copied from the task inline script)
# ---------------------------------------------------------------------------

def resolve_digest_to_git_sha(digest, container_image):
    try:
        repo_url = container_image.split('@')[0]
        if not repo_url.startswith('quay.io/'):
            print(f"  Not a quay.io image, skipping digest resolution")
            return None
        repo_path = repo_url.removeprefix('quay.io/')
        page = 1
        max_pages = 50
        while page <= max_pages:
            resp = requests.get(
                f"https://quay.io/api/v1/repository/{repo_path}/tag/",
                params={"limit": 100, "page": page},
                timeout=10,
            )
            if resp.status_code != 200:
                print(f"  Quay API returned {resp.status_code}, skipping digest resolution")
                return None
            data = resp.json()
            for tag in data.get("tags", []):
                if tag.get("manifest_digest") == digest and re.fullmatch(r'[0-9a-f]{40}', tag["name"]):
                    print(f"  Resolved {digest[:19]}... to git SHA {tag['name']}")
                    return tag["name"]
            if not data.get("has_additional", False):
                break
            page += 1
        print(f"  No git SHA tag found for digest {digest[:19]}...")
        return None
    except Exception as e:
        print(f"  Failed to resolve digest to git SHA: {e}")
        return None


def get_changelog(source_repo, old_rev, new_rev):
    try:
        owner_repo = '/'.join(source_repo.rstrip('/').split('/')[-2:])
        req = requests.get(
            f"{GITHUB_API_URL}/repos/{owner_repo}/compare/{old_rev}...{new_rev}",
            headers={"Accept": "application/vnd.github.v3+json"})
        if req.status_code != 200:
            print(f"  Compare API returned {req.status_code}, skipping changelog")
            return ""
        commits = req.json().get("commits", [])
        if not commits:
            return ""
        lines = ["## Changelog"]
        for c in commits:
            sha = c["sha"][:7]
            url = c["html_url"]
            msg = c["commit"]["message"].split('\n')[0]
            msg = re.sub(r'#(\d+)', rf'[#\1](https://github.com/{owner_repo}/pull/\1)', msg)
            author = c.get("author", {}).get("login") if c.get("author") else None
            if author:
                lines.append(f"- [`{sha}`]({url}) {msg} - @{author}")
            else:
                author_name = c["commit"]["author"]["name"]
                lines.append(f"- [`{sha}`]({url}) {msg} - {author_name}")
        return '\n'.join(lines)
    except Exception as e:
        print(f"  Failed to get changelog: {e}")
        return ""


# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

passed = 0
failed = 0


def check(name, condition):
    global passed, failed
    if condition:
        print(f"  PASS: {name}")
        passed += 1
    else:
        print(f"  FAIL: {name}")
        failed += 1


def header(title):
    print(f"\n{'=' * 60}")
    print(f"  {title}")
    print(f"{'=' * 60}")


# ---------------------------------------------------------------------------
# Fetch fresh valid SHAs from a public repo
# ---------------------------------------------------------------------------

print("Fetching fresh commits from konflux-ci/release-service...")
resp = requests.get(
    f"{GITHUB_API_URL}/repos/konflux-ci/release-service/commits?per_page=5",
    headers={"Accept": "application/vnd.github.v3+json"},
)
assert resp.status_code == 200, f"Cannot fetch commits (status {resp.status_code}), check rate limit"
commits = resp.json()
NEW_SHA = commits[0]["sha"]
OLD_SHA = commits[4]["sha"]
print(f"  old={OLD_SHA[:10]}  new={NEW_SHA[:10]}")


# ---------------------------------------------------------------------------
# get_changelog
# ---------------------------------------------------------------------------

header("get_changelog — happy path")
print(f"  Inputs: repo='konflux-ci/release-service' old={OLD_SHA[:10]} new={NEW_SHA[:10]}")
result = get_changelog("https://github.com/konflux-ci/release-service", OLD_SHA, NEW_SHA)
check("returns non-empty string", result != "")
check("starts with ## Changelog", result.startswith("## Changelog"))
check("contains commit links", "](https://github.com/" in result)
lines = result.strip().split('\n')
check(f"header + {len(lines)-1} commit entries", len(lines) >= 2)
print(f"\n  Output:\n{result}")

header("get_changelog — bare PR refs rewritten to full URLs")
print(f"  Inputs: repo='konflux-ci/release-service' old={OLD_SHA[:10]} new={NEW_SHA[:10]}")
result = get_changelog("https://github.com/konflux-ci/release-service", OLD_SHA, NEW_SHA)
pr_ref_pattern = re.compile(r'(?<![/\w])#\d+')
check("no bare #NNN references remain", not pr_ref_pattern.search(result))
full_url_pattern = re.compile(r'\[#\d+\]\(https://github\.com/konflux-ci/release-service/pull/\d+\)')
has_pr_ref = full_url_pattern.search(result) or '#' not in ''.join(
    c["commit"]["message"].split('\n')[0] for c in requests.get(
        f"{GITHUB_API_URL}/repos/konflux-ci/release-service/compare/{OLD_SHA}...{NEW_SHA}",
        headers={"Accept": "application/vnd.github.v3+json"}).json().get("commits", []))
check("PR refs expanded to full GitHub URLs (or none present)", has_pr_ref)
print(f"\n  Output:\n{result}")

header("get_changelog — nonexistent repo (graceful skip)")
print(f"  Inputs: repo='konflux-ci/doesnt-exist-xyz' old={OLD_SHA[:10]} new={NEW_SHA[:10]}")
result = get_changelog("https://github.com/konflux-ci/doesnt-exist-xyz", OLD_SHA, NEW_SHA)
print(f"  Result: {result!r}")
check("returns empty string", result == "")

header("get_changelog — invalid old SHA / semver (graceful skip)")
print(f"  Inputs: repo='konflux-ci/release-service' old='1.2.3' new={NEW_SHA[:10]}")
result = get_changelog("https://github.com/konflux-ci/release-service", "1.2.3", NEW_SHA)
print(f"  Result: {result!r}")
check("returns empty string", result == "")

header("get_changelog — same old and new SHA")
print(f"  Inputs: repo='konflux-ci/release-service' old={NEW_SHA[:10]} new={NEW_SHA[:10]}")
result = get_changelog("https://github.com/konflux-ci/release-service", NEW_SHA, NEW_SHA)
print(f"  Result: {result!r}")
check("returns empty string", result == "")

header("get_changelog — trailing slash in repo URL")
print(f"  Inputs: repo='konflux-ci/release-service/' old={OLD_SHA[:10]} new={NEW_SHA[:10]}")
result = get_changelog("https://github.com/konflux-ci/release-service/", OLD_SHA, NEW_SHA)
print(f"  Result:\n{result}")
check("returns non-empty string", result != "")
check("starts with ## Changelog", result.startswith("## Changelog"))


# ---------------------------------------------------------------------------
# resolve_digest_to_git_sha
# ---------------------------------------------------------------------------

header("resolve_digest_to_git_sha — non-quay image (skip)")
print(f"  Inputs: digest='sha256:abc' image='registry.io/org/repo@sha256:abc'")
result = resolve_digest_to_git_sha("sha256:abc", "registry.io/org/repo@sha256:abc")
print(f"  Result: {result!r}")
check("returns None", result is None)

header("resolve_digest_to_git_sha — wrong digest (no match)")
wrong_digest = "sha256:" + "0" * 64
print(f"  Inputs: digest='{wrong_digest[:25]}...' image='quay.io/konflux-ci/release-service-utils@...'")
result = resolve_digest_to_git_sha(
    wrong_digest,
    f"quay.io/konflux-ci/release-service-utils@{wrong_digest}",
)
print(f"  Result: {result!r}")
check("returns None", result is None)

header("resolve_digest_to_git_sha — real quay image with valid digest")
tag_resp = requests.get(
    "https://quay.io/api/v1/repository/konflux-ci/release-service-utils/tag/",
    params={"limit": 20},
    timeout=10,
)
real_digest = None
real_sha_tag = None
if tag_resp.status_code == 200:
    for tag in tag_resp.json().get("tags", []):
        if re.fullmatch(r'[0-9a-f]{40}', tag.get("name", "")):
            real_digest = tag["manifest_digest"]
            real_sha_tag = tag["name"]
            break

if real_digest and real_sha_tag:
    print(f"  Found tag: {real_sha_tag[:10]}... digest: {real_digest[:19]}...")
    result = resolve_digest_to_git_sha(
        real_digest,
        f"quay.io/konflux-ci/release-service-utils@{real_digest}",
    )
    print(f"  Result: {result!r}")
    check("resolves to correct git SHA", result == real_sha_tag)
else:
    print("  SKIP: no SHA-tagged image found on quay.io")

header("resolve_digest_to_git_sha — nonexistent quay repo")
print(f"  Inputs: digest='sha256:abc' image='quay.io/nonexistent-org-xyz/nonexistent-repo@sha256:abc'")
result = resolve_digest_to_git_sha(
    "sha256:abc",
    "quay.io/nonexistent-org-xyz/nonexistent-repo@sha256:abc",
)
print(f"  Result: {result!r}")
check("returns None", result is None)


# ---------------------------------------------------------------------------
# Pure logic: URL parsing and branch name derivation
# ---------------------------------------------------------------------------

header("owner/repo extraction from URL")

def extract_owner_repo(url):
    return '/'.join(url.rstrip('/').split('/')[-2:])

for url in ["https://github.com/org/repo", "https://github.com/org/repo/", "https://github.com/konflux-ci/release-service"]:
    print(f"  {url} -> {extract_owner_repo(url)}")
check("standard URL", extract_owner_repo("https://github.com/org/repo") == "org/repo")
check("trailing slash", extract_owner_repo("https://github.com/org/repo/") == "org/repo")
check("real URL", extract_owner_repo("https://github.com/konflux-ci/release-service") == "konflux-ci/release-service")

header("branch name from originRepo")

def branch_name(origin):
    return origin.split('/')[-1]

for url in ["https://github.com/org/my-component", "https://github.com/org/my-component.git"]:
    print(f"  {url} -> {branch_name(url)}")
check("simple", branch_name("https://github.com/org/my-component") == "my-component")
check("with .git suffix", branch_name("https://github.com/org/my-component.git") == "my-component.git")


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print(f"\n{'=' * 60}")
total = passed + failed
print(f"  RESULTS: {passed}/{total} passed, {failed} failed")
print(f"{'=' * 60}")

sys.exit(1 if failed else 0)
