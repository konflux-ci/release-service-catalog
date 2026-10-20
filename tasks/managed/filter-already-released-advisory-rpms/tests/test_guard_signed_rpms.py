"""Exercise the enabled signed-Pulp guard embedded in the managed Task."""

import json
import os
import sys
import tempfile
import types
import unittest
from enum import Enum
from pathlib import Path
from typing import ClassVar
from unittest.mock import patch
from urllib.parse import parse_qs, urlparse

import yaml

TASK_FILE = (
    Path(__file__).resolve().parents[1] / "filter-already-released-advisory-rpms.yaml"
)
TASK = yaml.safe_load(TASK_FILE.read_text(encoding="utf-8"))
GUARD_SCRIPT = next(
    step["script"]
    for step in TASK["spec"]["steps"]
    if step["name"] == "guard-signed-rpms"
)


class DigestStatus(Enum):
    MATCH = "match"
    MISMATCH = "mismatch"
    NOT_FOUND = "not_found"


class FakePulp:
    published: ClassVar[dict] = {}
    latest: ClassVar[set] = set()
    repository_exists: ClassVar[bool] = True
    calls: ClassVar[list] = []

    def __init__(self, _session, _base_url, _domain):
        pass

    def check_digest(self, repo, name, _epoch, _version, _release, arch, _sha):
        self.calls.append(("published", repo, name, arch))
        return self.published.get((repo, name, arch), DigestStatus.NOT_FOUND)

    def get_json(self, url):
        parsed = urlparse(url)
        query = parse_qs(parsed.query)
        if parsed.path.endswith("/repositories/rpm/rpm/"):
            repo = query["name"][0]
            self.calls.append(("repository", repo))
            if not self.repository_exists:
                return {"results": []}
            return {"results": [{"name": repo, "pulp_href": f"/repo/{repo}/"}]}
        if parsed.path.startswith("/repo/"):
            repo = parsed.path.split("/")[2]
            self.calls.append(("repository_version", repo))
            return {"latest_version_href": f"/repo/{repo}/latest/"}
        if parsed.path.endswith("/content/rpm/packages/"):
            version = query["repository_version"][0]
            repo = version.split("/")[2]
            rpm = (
                repo,
                query["name"][0],
                query["epoch"][0],
                query["version"][0],
                query["release"][0],
                query["arch"][0],
            )
            self.calls.append(("latest", *rpm))
            return {"count": int(rpm in self.latest), "results": []}
        raise AssertionError(f"Unexpected Pulp request: {url}")


def rpm(name, repo="x86_64"):
    return {
        "rpm": f"{name}-1-1.x86_64.rpm",
        "rpmname": name,
        "epoch": "0",
        "version": "1",
        "release": "1",
        "arch": "x86_64",
        "sha256": "unsigned-sha",
        "targetRepos": [{"repository_name": repo}],
    }


class TestSignedPulpGuard(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        root = Path(self.temp_dir.name)
        self.snapshot = root / "snapshot.json"
        self.skip = root / "skip"
        self.config = root / "cli.toml"
        self.snapshot.write_text(
            json.dumps({"components": [{"rpmsToPublish": [rpm("new")]}]})
        )
        self.skip.write_text("false")
        self.config.write_text("")
        FakePulp.published = {}
        FakePulp.latest = set()
        FakePulp.repository_exists = True
        FakePulp.calls = []

    def run_guard(self, domain="signed"):
        root_module = types.ModuleType("release_service_utils")
        root_module.__path__ = []
        helpers = types.ModuleType("release_service_utils.helpers")
        helpers.__path__ = []
        http_client = types.ModuleType("release_service_utils.helpers.http_client")
        http_client.get_retry_session = lambda **_kwargs: types.SimpleNamespace(
            auth=None
        )
        pulp_client = types.ModuleType("release_service_utils.helpers.pulp_client")
        pulp_client.PulpAuth = lambda _config: None
        pulp_client.PulpClient = FakePulp
        pulp_client.PulpDigestStatus = DigestStatus
        pulp_client.parse_pulp_config = lambda _path: {
            "base_url": "https://pulp.example"
        }
        helpers.http_client = http_client
        modules = {
            "release_service_utils": root_module,
            "release_service_utils.helpers": helpers,
            "release_service_utils.helpers.http_client": http_client,
            "release_service_utils.helpers.pulp_client": pulp_client,
        }
        env = {
            "SIGNED_PULP_DOMAIN": domain,
            "RESULT_SKIP_RELEASE": str(self.skip),
            "SNAPSHOT_FILE": str(self.snapshot),
            "PULP_CONFIG_FILE": str(self.config),
        }
        with patch.dict(sys.modules, modules), patch.dict(os.environ, env):
            # Execute the Task's actual embedded script with fake Pulp modules.
            exec(compile(GUARD_SCRIPT, str(TASK_FILE), "exec"), {})  # noqa: S102

    def test_absent_from_published_and_latest_allows_retry(self):
        self.run_guard()
        self.assertIn(("published", "x86_64", "new", "x86_64"), FakePulp.calls)
        self.assertIn(
            ("latest", "x86_64", "new", "0", "1", "1", "x86_64"), FakePulp.calls
        )

    def test_stale_publication_still_blocks_retry(self):
        FakePulp.latest.add(("x86_64", "new", "0", "1", "1", "x86_64"))
        with self.assertRaisesRegex(RuntimeError, "Stop before re-signing"):
            self.run_guard()
        self.assertIn(
            ("latest", "x86_64", "new", "0", "1", "1", "x86_64"), FakePulp.calls
        )

    def test_published_rpm_blocks_retry(self):
        FakePulp.published[("x86_64", "new", "x86_64")] = DigestStatus.MISMATCH
        with self.assertRaisesRegex(RuntimeError, "Stop before re-signing"):
            self.run_guard()
        self.assertNotIn(
            ("latest", "x86_64", "new", "0", "1", "1", "x86_64"), FakePulp.calls
        )

    def test_partial_release_stops_before_resigning_completed_rpm(self):
        self.snapshot.write_text(
            json.dumps(
                {
                    "components": [
                        {
                            "rpmsToPublish": [
                                rpm("released"),
                                rpm("new"),
                            ]
                        }
                    ]
                }
            )
        )
        FakePulp.published[("x86_64", "released", "x86_64")] = DigestStatus.MISMATCH
        with self.assertRaisesRegex(RuntimeError, "partial release"):
            self.run_guard()
        self.assertNotIn(("published", "x86_64", "new", "x86_64"), FakePulp.calls)

    def test_missing_signed_repository_fails_closed(self):
        FakePulp.repository_exists = False
        with self.assertRaisesRegex(
            RuntimeError, "Cannot identify signed Pulp repository"
        ):
            self.run_guard()

    def test_completed_advisory_skips_guard(self):
        self.skip.write_text("true")
        self.run_guard()
        self.assertEqual(FakePulp.calls, [])

    def test_empty_domain_skips_guard(self):
        self.run_guard(domain="")
        self.assertEqual(FakePulp.calls, [])


if __name__ == "__main__":
    unittest.main()
