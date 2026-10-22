"""Stub python-gitlab for create-advisory Tekton unit tests."""

from __future__ import annotations

import sys
from types import ModuleType, SimpleNamespace
from typing import Any


class GitlabError(Exception):
    def __init__(self, message: str, response_code: int | None = None) -> None:
        super().__init__(message)
        self.response_code = response_code


class GitlabConnectionError(GitlabError):
    pass


_exceptions = ModuleType("gitlab.exceptions")
_exceptions.GitlabError = GitlabError
_exceptions.GitlabConnectionError = GitlabConnectionError
sys.modules["gitlab.exceptions"] = _exceptions
exceptions = _exceptions


class _Approvals:
    def __init__(self, merge_request: "_MergeRequest") -> None:
        self._merge_request = merge_request

    def get(self, **_kwargs: Any) -> SimpleNamespace:
        merge_request = self._merge_request
        stored = merge_request.manager._by_iid[merge_request.iid]
        return SimpleNamespace(user_has_approved=stored.user_has_approved)


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
        self.sha = "mockheadsha"
        self.user_has_approved = False
        self.approvals = _Approvals(self)
        self.merge_status = "cannot_be_merged"
        self.detailed_merge_status = "not_approved"
        self.merge_commit_sha: str | None = None
        self.is_on_merge_train = False
        self.was_merge_train_entry_read = False
        self.manager = manager
        self._attrs = self._current_attrs()

    def _current_attrs(self) -> dict[str, Any]:
        return {
            "iid": self.iid,
            "web_url": self.web_url,
            "source_branch": self.source_branch,
            "state": self.state,
            "sha": self.sha,
            "user_has_approved": self.user_has_approved,
            "merge_status": self.merge_status,
            "detailed_merge_status": self.detailed_merge_status,
            "merge_commit_sha": self.merge_commit_sha,
            "is_on_merge_train": self.is_on_merge_train,
            "was_merge_train_entry_read": self.was_merge_train_entry_read,
        }

    def get_id(self) -> int:
        return self.iid

    def approve(self, sha: str | None = None, **_kwargs: Any) -> dict[str, Any]:
        stored = self.manager._by_iid[self.iid]
        if sha != stored.sha:
            raise GitlabError("HEAD SHA does not match", response_code=409)
        # Apply only this operation's changes; the caller may hold a stale snapshot.
        stored._update_attrs({
            "user_has_approved": True,
            "merge_status": "can_be_merged",
            "detailed_merge_status": "mergeable",
        })
        self._update_attrs(stored._current_attrs())
        return {"user_has_approved": True}

    def merge(self, **_kwargs: Any) -> dict[str, Any]:
        stored = self.manager._by_iid[self.iid]
        if not stored.user_has_approved:
            raise GitlabError("Approval required", response_code=405)
        stored._update_attrs({
            "state": "merged",
            "merge_commit_sha": "mockmergecommitsha",
        })
        self._update_attrs(stored._current_attrs())
        return dict(self._attrs)

    def merge_train_entry(self) -> dict[str, Any]:
        status = "merged" if self.state == "merged" else "idle"
        return {
            "id": self.iid,
            "project_id": self.manager._project.id,
            "merge_request_iid": self.iid,
            "state": status,
            "status": status,
            "merge_request": {
                "iid": self.iid,
                "state": self.state,
                "web_url": self.web_url,
            },
        }

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
        if stored.is_on_merge_train and stored.was_merge_train_entry_read:
            stored.merge()
        fresh = _MergeRequest(
            stored.iid,
            stored.web_url,
            source_branch=stored.source_branch,
            manager=self,
        )
        fresh._update_attrs(stored._current_attrs())
        return fresh


class _Project:
    def __init__(self, project_id: int, path: str) -> None:
        self.id = project_id
        self.path = path
        self.mergerequests = _MergeRequestManager(self)


class _ProjectsManager:
    def __init__(self) -> None:
        self._by_path: dict[str, _Project] = {}
        self._by_id: dict[int, _Project] = {}
        self._next_id = 1

    def get(self, project_path: str, **_kwargs: Any) -> _Project:
        path = str(project_path)
        if path not in self._by_path:
            project = _Project(self._next_id, path)
            self._next_id += 1
            self._by_path[path] = project
            self._by_id[project.id] = project
        return self._by_path[path]

    def get_by_id(self, project_id: int) -> _Project:
        return self._by_id[int(project_id)]


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

    def _merge_train_merge_request(self, path: str) -> _MergeRequest | None:
        parts = [part for part in path.strip("/").split("/") if part]
        if (
            len(parts) == 5
            and parts[0] == "projects"
            and parts[2] == "merge_trains"
            and parts[3] == "merge_requests"
        ):
            project = self.projects.get_by_id(int(parts[1]))
            return project.mergerequests._by_iid[int(parts[4])]
        return None

    def http_post(self, path: str, **_kwargs: Any) -> dict[str, Any]:
        merge_request = self._merge_train_merge_request(path)
        if merge_request is not None:
            stored = merge_request.manager._by_iid[merge_request.iid]
            stored._update_attrs({"is_on_merge_train": True})
            return stored.merge_train_entry()
        raise GitlabError(f"unexpected POST {path}", response_code=404)

    def http_get(self, path: str, **_kwargs: Any) -> dict[str, Any]:
        merge_request = self._merge_train_merge_request(path)
        if merge_request is not None:
            stored = merge_request.manager._by_iid[merge_request.iid]
            stored._update_attrs({"was_merge_train_entry_read": True})
            return stored.merge_train_entry()
        raise GitlabError(f"unexpected GET {path}", response_code=404)


__all__ = ["Gitlab", "GitlabError", "GitlabConnectionError", "exceptions"]
