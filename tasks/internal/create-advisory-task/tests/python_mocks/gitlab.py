"""Stub python-gitlab for create-advisory Tekton unit tests."""

from __future__ import annotations

import sys
from types import ModuleType
from typing import Any


class GitlabError(Exception):
    pass


class GitlabConnectionError(GitlabError):
    pass


_exceptions = ModuleType("gitlab.exceptions")
_exceptions.GitlabError = GitlabError
_exceptions.GitlabConnectionError = GitlabConnectionError
sys.modules["gitlab.exceptions"] = _exceptions
exceptions = _exceptions


class _MergeRequest:
    def __init__(
        self,
        iid: int,
        web_url: str,
        *,
        source_branch: str,
        manager: "_MergeRequestManager",
    ) -> None:
        self.iid = iid
        self.web_url = web_url
        self.source_branch = source_branch
        self.state = "opened"
        self.merge_status = "can_be_merged"
        self.merge_commit_sha: str | None = None
        self.manager = manager
        self._attrs = self._current_attrs()

    def _current_attrs(self) -> dict[str, Any]:
        return {
            "iid": self.iid,
            "web_url": self.web_url,
            "source_branch": self.source_branch,
            "state": self.state,
            "merge_status": self.merge_status,
            "merge_commit_sha": self.merge_commit_sha,
        }

    def get_id(self) -> int:
        return self.iid

    def merge(self, **_kwargs: Any) -> dict[str, Any]:
        self.state = "merged"
        self.merge_commit_sha = "mockmergecommitsha"
        self._attrs = self._current_attrs()
        return dict(self._attrs)

    def _update_attrs(self, attrs: dict[str, Any]) -> None:
        for key, value in attrs.items():
            setattr(self, key, value)
        self._attrs = self._current_attrs()


class _MergeRequestManager:
    def __init__(self, project: "_Project") -> None:
        self._project = project
        self._by_iid: dict[int, _MergeRequest] = {}
        self._next_iid = 1

    def list(self, **kwargs: Any) -> list[_MergeRequest]:
        state = kwargs.get("state", "opened")
        source_branch = kwargs.get("source_branch")
        found: list[_MergeRequest] = []
        for merge_request in self._by_iid.values():
            if state == "opened" and merge_request.state != "opened":
                continue
            if source_branch and merge_request.source_branch != source_branch:
                continue
            found.append(merge_request)
        return found[: int(kwargs.get("per_page", 20))]

    def create(self, data: dict[str, Any]) -> _MergeRequest:
        iid = self._next_iid
        self._next_iid += 1
        web_url = (
            f"https://gitlab.example.com/{self._project.path}"
            f"/-/merge_requests/{iid}"
        )
        merge_request = _MergeRequest(
            iid,
            web_url,
            source_branch=str(data.get("source_branch", "")),
            manager=self,
        )
        self._by_iid[iid] = merge_request
        return merge_request

    def get(self, iid: int, **_kwargs: Any) -> _MergeRequest:
        stored = self._by_iid[int(iid)]
        fresh = _MergeRequest(
            stored.iid,
            stored.web_url,
            source_branch=stored.source_branch,
            manager=self,
        )
        fresh.state = stored.state
        fresh.merge_status = stored.merge_status
        fresh.merge_commit_sha = stored.merge_commit_sha
        fresh._attrs = fresh._current_attrs()
        return fresh


class _Project:
    def __init__(self, path: str) -> None:
        self.path = path
        self.mergerequests = _MergeRequestManager(self)


class _ProjectsManager:
    def __init__(self) -> None:
        self._by_path: dict[str, _Project] = {}

    def get(self, project_path: str, **_kwargs: Any) -> _Project:
        path = str(project_path)
        if path not in self._by_path:
            self._by_path[path] = _Project(path)
        return self._by_path[path]


class Gitlab:
    def __init__(
        self,
        url: str,
        private_token: str | None = None,
        timeout: float | None = None,
        **_kwargs: Any,
    ) -> None:
        self.url = url
        self.private_token = private_token
        self.timeout = timeout
        self.projects = _ProjectsManager()


__all__ = ["Gitlab", "GitlabError", "GitlabConnectionError", "exceptions"]
