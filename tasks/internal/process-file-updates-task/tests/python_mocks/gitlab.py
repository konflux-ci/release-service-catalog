"""Stub gitlab for Tekton tests (no live GitLab credentials)."""

from __future__ import annotations

import sys
from types import ModuleType
from typing import Any


class GitlabError(Exception):
    pass


_exceptions = ModuleType("gitlab.exceptions")
_exceptions.GitlabError = GitlabError
sys.modules["gitlab.exceptions"] = _exceptions
exceptions = _exceptions


class Gitlab:
    def __init__(self, url: str, private_token: str | None = None) -> None:
        self.projects = _ProjectsManager()


class _ProjectsManager:
    def get(self, project_path: str) -> _Project:
        return _Project(project_path)


class _Project:
    def __init__(self, project_path: str) -> None:
        self.mergerequests = _MergeRequestsManager(project_path)


class _MergeRequestsManager:
    def __init__(self, project_path: str) -> None:
        self._project_path = project_path

    def _mr_web_url(self, iid: int = 1) -> str:
        """Build a stable MR URL from the GitLab project path (``group/project``, no ``.git``)."""
        repo_name = self._project_path.rsplit("/", 1)[-1]
        return f"https://some.gitlab/test/{repo_name}.git/-/merge_request/{iid}"

    def list(self, **kwargs: Any) -> list[_MergeRequest]:
        page = int(kwargs.get("page", 1))
        search = str(kwargs.get("search", ""))
        prefix = "[Konflux release] "
        # Require scoped search with componentGroup (e.g. "[Konflux release] scott"),
        # not just the prefix. Reject broad "[Konflux release]" without component group.
        if page != 1 or not search.startswith(prefix) or len(search) <= len(prefix):
            return []
        # Return existing MR only for repos explicitly testing idempotency/duplicate detection.
        # "one-update" tests new-MR creation, so return no existing MRs for it.
        if "idempotent" in self._project_path:
            return [_MergeRequest(1, self._mr_web_url(1))]
        return []

    def create(self, data: dict[str, Any]) -> _MergeRequest:
        return _MergeRequest(1, self._mr_web_url(1))


class _MergeRequest:
    def __init__(self, iid: int, web_url: str) -> None:
        self.iid = iid
        self.web_url = web_url


__all__ = ["Gitlab", "GitlabError"]
