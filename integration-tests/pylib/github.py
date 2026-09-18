"""
GitHub API client for integration tests.

Provides async methods for GitHub repository and PR operations using PyGithub.
"""

import asyncio
from dataclasses import dataclass
from pathlib import Path

from github import Auth, Github
from github.GithubException import GithubException

from .utils import log_error, log_info, log_warning, run_command, run_with_retry


@dataclass
class MergeResult:
    """Result of a PR merge operation."""

    sha: str
    merged: bool
    message: str


class GitHubClient:
    """
    Async GitHub API client using PyGithub.

    Provides methods for:
    - Repository operations (get, delete, create from template)
    - Pull request operations (get, merge)
    - Release verification
    """

    def __init__(self, token: str):
        """Initialize the GitHub client."""
        self.gh = Github(auth=Auth.Token(token))

    async def get_repo(self, repo_name: str) -> dict | None:
        """Get repository information."""
        try:
            repo = await asyncio.to_thread(self.gh.get_repo, repo_name)
            return {"full_name": repo.full_name, "html_url": repo.html_url}
        except GithubException as e:
            if e.status == 404:
                return None
            raise

    async def delete_repo(self, repo_name: str) -> bool:
        """Delete a repository."""
        try:
            repo = await asyncio.to_thread(self.gh.get_repo, repo_name)
            await asyncio.to_thread(repo.delete)
            log_info(f"Deleted repository: {repo_name}")
            return True
        except GithubException as e:
            if e.status == 404:
                log_warning(f"Repository {repo_name} not found (already deleted?)")
                return False
            raise

    async def create_repo_from_template(
        self,
        template_repo: str,
        new_repo_name: str,
        owner: str,
        private: bool = False,
    ) -> dict:
        """Create a repository from a template."""
        template = await asyncio.to_thread(self.gh.get_repo, template_repo)
        repo = await asyncio.to_thread(
            template.create_repo_from_template, new_repo_name, private=private
        )
        return {"full_name": repo.full_name, "html_url": repo.html_url}

    async def get_pr(self, repo_name: str, pr_number: int) -> dict | None:
        """Get pull request information."""
        try:
            repo = await asyncio.to_thread(self.gh.get_repo, repo_name)
            pr = await asyncio.to_thread(repo.get_pull, pr_number)
            return {"number": pr.number, "state": pr.state, "merged": pr.merged}
        except GithubException as e:
            if e.status == 404:
                return None
            raise

    async def merge_pr(
        self,
        repo_name: str,
        pr_number: int,
        commit_title: str = "e2e test",
        commit_message: str = "e2e test",
    ) -> MergeResult:
        """Merge a pull request with retry logic."""

        async def do_merge() -> MergeResult:
            repo = await asyncio.to_thread(self.gh.get_repo, repo_name)
            pr = await asyncio.to_thread(repo.get_pull, pr_number)
            result = await asyncio.to_thread(
                pr.merge, commit_title=commit_title, commit_message=commit_message
            )
            return MergeResult(
                sha=result.sha or "",
                merged=result.merged,
                message=result.message or "",
            )

        result = await run_with_retry(
            do_merge,
            max_attempts=3,
            delay_seconds=5,
            description=f"Merge PR #{pr_number} in {repo_name}",
        )

        if result.merged:
            log_info(f"Merged PR #{pr_number} in {repo_name}, SHA: {result.sha[:8]}")
        else:
            log_error(f"Failed to merge PR #{pr_number}: {result.message}")

        return result

    async def add_comment(self, repo_name: str, pr_number: int, body: str) -> None:
        """Add a comment to a pull request."""
        repo = await asyncio.to_thread(self.gh.get_repo, repo_name)
        issue = await asyncio.to_thread(repo.get_issue, pr_number)
        await asyncio.to_thread(issue.create_comment, body)

    async def get_release(self, repo_name: str, tag: str) -> dict | None:
        """Get a GitHub release by tag."""
        try:
            repo = await asyncio.to_thread(self.gh.get_repo, repo_name)
            release = await asyncio.to_thread(repo.get_release, tag)
            return {"tag_name": release.tag_name, "html_url": release.html_url}
        except GithubException as e:
            if e.status == 404:
                return None
            raise

    async def release_exists(self, repo_name: str, tag: str) -> bool:
        """Check if a GitHub release with the given tag exists."""
        return await self.get_release(repo_name, tag) is not None


# Script-based Operations (for compatibility with existing bash scripts)


async def copy_branch_to_repo(
    base_repo: str,
    base_branch: str,
    new_repo: str,
    new_branch: str,
    scripts_dir: str,
) -> None:
    """Copy a branch from one repo to a new repo using bash script."""
    script_path = Path(scripts_dir) / "copy-branch-to-repo-git.sh"
    await run_command([str(script_path), base_repo, base_branch, new_repo, new_branch])
    log_info(f"Created {new_repo}:{new_branch} from {base_repo}:{base_branch}")


async def delete_repository(repo_name: str, scripts_dir: str) -> None:
    """Delete a GitHub repository using the bash script."""
    script_path = Path(scripts_dir) / "delete-repository.sh"
    await run_command([str(script_path), repo_name], check=False)
    log_info(f"Deleted repository: {repo_name}")
