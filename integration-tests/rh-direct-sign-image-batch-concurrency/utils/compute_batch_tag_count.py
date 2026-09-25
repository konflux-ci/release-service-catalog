#!/usr/bin/env python3
"""compute_batch_tag_count.py - Compute the exact tag count that forces
rh_direct_sign_image.py's batch_signing_items() to split into a target
number of concurrently-submitted signing batches.

Rather than re-implementing rh_direct_sign_image.py's batching/item-collection
logic (which would silently drift from production as that script evolves),
this script imports and calls the real functions directly:
``collect_signing_items``, ``batch_signing_items``, ``get_all_image_digests``,
and ``get_signing_keys``. This accounts for details easy to miss in a
reimplementation, such as multi-arch images contributing one signing item per
extra manifest digest, and the destination repository string being converted
from its quay.io temp-namespace form to its registry.redhat.io form (as
apply_mapping.py does) before being embedded in each signing reference.
The suite must still verify the actual batch count: the runner and signing
task can use different utils versions, and Pyxis filtering of existing
signatures can change the final batch count.

This script only runs inside a release-service-catalog/release-service-utils
test-runner container, where ``rh_direct_sign_image`` is always importable
(release-service-catalog's own image is built ``FROM`` release-service-utils,
which puts it on PYTHONPATH as a flat top-level module).

Usage:
  compute_batch_tag_count.py \
      --source-image quay.io/redhat-user-workloads-stage/dev-release-team-tenant/foo@sha256:<64 hex> \
      --signing-repo quay.io/redhat-pending/rhtap----rh-advisories-component \
      --configmap-name hacbs-signing-pipeline-config-staging-e2e-pq \
      --namespace managed-release-team-tenant \
      --pyxis-server stage \
      --pyxis-cert /path/to/cert \
      --pyxis-key /path/to/key \
      --tag-prefix batch-concur-abcd1234 \
      --implicit-tag 1722233849 \
      --batch-limit 15000 \
      --target-batches 2 \
      --margin 5

Prints the computed tag count to stdout. Diagnostics (resolved signing keys,
digests, batch sizes at the chosen count) are printed to stderr.
"""

from __future__ import annotations

import argparse
import sys

from publish_pyxis_repository import should_add_sign_registry_access
from release_service_utils.helpers import pyxis_api
from release_service_utils.helpers.image_ref import (
    convert_to_registry,
    convert_to_registry_access,
)
from release_service_utils.helpers.kubectl import get_configmap
from rh_direct_sign_image import (
    batch_signing_items,
    collect_signing_items,
    get_all_image_digests,
    get_signing_keys,
)


def build_component(
    rh_registry_repo: str,
    registry_access_repo: str,
    tags: list[str],
) -> dict:
    """Build the minimal post-apply_mapping component dict collect_signing_items() expects.

    Includes the same Red Hat and registry-access repository variants that
    apply-mapping supplies to the signing task.
    """
    return {
        "repositories": [
            {
                "rh-registry-repo": rh_registry_repo,
                "registry-access-repo": registry_access_repo,
                "tags": tags,
            }
        ]
    }


def tags_for_tag_count(num_tags: int, tag_prefix: str, implicit_tag: str) -> list[str]:
    """Return tags in the same order produced by apply-mapping's jq `unique`."""
    return sorted({*(f"{tag_prefix}-{i:04d}" for i in range(num_tags)), implicit_tag})


def batches_for_tag_count(
    num_tags: int,
    rh_registry_repo: str,
    registry_access_repo: str,
    sign_registry_access_repos: set[str],
    digests: list[str],
    signing_keys: list[str],
    tag_prefix: str,
    implicit_tag: str,
    batch_limit: int,
) -> list[str]:
    """Return the signing batches production would produce for ``num_tags`` tags."""
    # apply-mapping appends the image timestamp tag and then jq's `unique`
    # sorts and deduplicates the complete tag list before signing.
    tags = tags_for_tag_count(num_tags, tag_prefix, implicit_tag)
    component = build_component(rh_registry_repo, registry_access_repo, tags)
    items = collect_signing_items(
        component,
        sign_registry_access_repos=sign_registry_access_repos,
        digests=digests,
        source_container_digest=None,
        signing_keys=signing_keys,
    )
    return batch_signing_items(items, max_batch_bytes=batch_limit)


def find_minimal_tag_count(
    rh_registry_repo: str,
    registry_access_repo: str,
    sign_registry_access_repos: set[str],
    digests: list[str],
    signing_keys: list[str],
    tag_prefix: str,
    implicit_tag: str,
    batch_limit: int,
    target_batches: int,
    upper_bound: int,
) -> int:
    """Find the smallest tag count producing the target via exponential/binary search."""

    def batch_count(num_tags: int) -> int:
        return len(
            batches_for_tag_count(
                num_tags,
                rh_registry_repo,
                registry_access_repo,
                sign_registry_access_repos,
                digests,
                signing_keys,
                tag_prefix,
                implicit_tag,
                batch_limit,
            )
        )

    lower = 0
    upper = 1
    upper_count = batch_count(upper)
    while upper_count < target_batches and upper < upper_bound:
        lower = upper
        upper = min(upper * 2, upper_bound)
        upper_count = batch_count(upper)

    if upper_count < target_batches:
        raise RuntimeError(
            f"Could not reach target_batches={target_batches} within "
            f"upper_bound={upper_bound} tags"
        )

    low = lower + 1
    high = upper
    while low < high:
        midpoint = (low + high) // 2
        if batch_count(midpoint) < target_batches:
            low = midpoint + 1
        else:
            high = midpoint

    selected_count = batch_count(low)
    if selected_count != target_batches:
        raise RuntimeError(
            f"Overshot target_batches={target_batches} at tags={low} "
            f"(got {selected_count} batches) without ever hitting the target exactly. "
            "Check --batch-limit, the signing ConfigMap, and the image manifest list."
        )
    return low


def find_tag_count_with_margin(
    rh_registry_repo: str,
    registry_access_repo: str,
    sign_registry_access_repos: set[str],
    digests: list[str],
    signing_keys: list[str],
    tag_prefix: str,
    implicit_tag: str,
    batch_limit: int,
    target_batches: int,
    margin: int,
    upper_bound: int,
) -> int:
    """Find a tag count comfortably inside the target_batches window, not on its edge.

    Starts at the minimal tag count that first reaches target_batches, then adds
    `margin` extra tags at a time (re-checking after each addition) as long as the
    batch count stays exactly target_batches. This lands well past the lower
    boundary without risking crossing into target_batches + 1.
    """
    minimal = find_minimal_tag_count(
        rh_registry_repo,
        registry_access_repo,
        sign_registry_access_repos,
        digests,
        signing_keys,
        tag_prefix,
        implicit_tag,
        batch_limit,
        target_batches,
        upper_bound,
    )

    chosen = minimal
    for candidate in range(minimal + 1, minimal + margin + 1):
        if candidate > upper_bound:
            break
        batch_count = len(
            batches_for_tag_count(
                candidate,
                rh_registry_repo,
                registry_access_repo,
                sign_registry_access_repos,
                digests,
                signing_keys,
                tag_prefix,
                implicit_tag,
                batch_limit,
            )
        )
        if batch_count != target_batches:
            print(
                f"note: stopping margin expansion at {chosen} tags — "
                f"{candidate} tags would produce {batch_count} batches, not {target_batches}",
                file=sys.stderr,
            )
            break
        chosen = candidate

    return chosen


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source-image",
        required=True,
        help="Resolved 'repo@sha256:<hex>' of the test image (fed to get_all_image_digests)",
    )
    parser.add_argument(
        "--signing-repo",
        required=True,
        help=(
            "Destination repo URL as configured in the RPA mapping (quay.io temp-namespace "
            "form, e.g. quay.io/redhat-pending/foo----bar); converted to its registry.redhat.io "
            "form via convert_to_registry(), matching what apply_mapping.py produces"
        ),
    )
    parser.add_argument(
        "--configmap-name",
        required=True,
        help="Signing ConfigMap name (SIG_KEY_NAMES/SIG_KEY_NAME)",
    )
    parser.add_argument(
        "--namespace", required=True, help="Namespace containing the signing ConfigMap"
    )
    parser.add_argument(
        "--pyxis-server",
        required=True,
        help="Pyxis server used by the release (for example, 'stage')",
    )
    parser.add_argument(
        "--pyxis-cert", required=True, help="Path to the Pyxis client certificate"
    )
    parser.add_argument(
        "--pyxis-key", required=True, help="Path to the Pyxis client key"
    )
    parser.add_argument(
        "--tag-prefix",
        required=True,
        help="Tag prefix; tags are '<prefix>-0000', '<prefix>-0001', ...",
    )
    parser.add_argument(
        "--implicit-tag",
        required=True,
        help="Image timestamp tag implicitly added by apply-mapping",
    )
    parser.add_argument(
        "--batch-limit", type=int, default=15000, help="Max encoded batch bytes"
    )
    parser.add_argument(
        "--target-batches", type=int, default=2, help="Desired exact batch count"
    )
    parser.add_argument(
        "--margin",
        type=int,
        default=5,
        help="Extra tags past the minimal boundary, if safe",
    )
    parser.add_argument(
        "--upper-bound", type=int, default=5000, help="Safety cap on tags to search"
    )
    args = parser.parse_args(argv)
    if args.target_batches < 2:
        parser.error(
            "--target-batches must be at least 2 to exercise multiple requests"
        )
    if args.batch_limit <= 0 or args.upper_bound <= 0 or args.margin < 0:
        parser.error(
            "--batch-limit and --upper-bound must be positive; --margin must be non-negative"
        )
    return args


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    configmap = get_configmap(args.configmap_name, namespace=args.namespace)
    signing_keys = get_signing_keys(configmap)
    print(f"Signing keys: {signing_keys}", file=sys.stderr)

    digests = get_all_image_digests(args.source_image)
    print(f"Resolved digests ({len(digests)}): {digests}", file=sys.stderr)

    rh_registry_repo = convert_to_registry(args.signing_repo)
    if not rh_registry_repo:
        print(
            f"error: --signing-repo '{args.signing_repo}' is not a recognized "
            "quay.io temp-namespace repository (see convert_to_registry())",
            file=sys.stderr,
        )
        return 1
    print(f"rh-registry-repo: {rh_registry_repo}", file=sys.stderr)

    registry_access_repo = convert_to_registry_access(rh_registry_repo)
    pyxis_registry = pyxis_api.pyxis_registry_for_quay_url(args.signing_repo)
    pyxis_repository = pyxis_api.pyxis_repository_from_quay_url(args.signing_repo)
    repository_json = pyxis_api.get_repository_json(
        pyxis_api.pyxis_api_url_for_server(args.pyxis_server),
        pyxis_registry,
        pyxis_repository,
        cert=(args.pyxis_cert, args.pyxis_key),
    )
    sign_registry_access_repos: set[str] = set()
    if should_add_sign_registry_access(
        pyxis_registry,
        repository_json.get("requires_terms"),
    ):
        if not registry_access_repo:
            print(
                f"error: cannot derive registry-access repo from '{rh_registry_repo}'",
                file=sys.stderr,
            )
            return 1
        sign_registry_access_repos.add(pyxis_repository)
    print(
        "registry-access signing: "
        f"{'enabled' if sign_registry_access_repos else 'disabled'} "
        f"(requires_terms={repository_json.get('requires_terms')!r})",
        file=sys.stderr,
    )

    try:
        chosen = find_tag_count_with_margin(
            rh_registry_repo=rh_registry_repo,
            registry_access_repo=registry_access_repo,
            sign_registry_access_repos=sign_registry_access_repos,
            digests=digests,
            signing_keys=signing_keys,
            tag_prefix=args.tag_prefix,
            implicit_tag=args.implicit_tag,
            batch_limit=args.batch_limit,
            target_batches=args.target_batches,
            margin=args.margin,
            upper_bound=args.upper_bound,
        )
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    final_batches = batches_for_tag_count(
        chosen,
        rh_registry_repo,
        registry_access_repo,
        sign_registry_access_repos,
        digests,
        signing_keys,
        args.tag_prefix,
        args.implicit_tag,
        args.batch_limit,
    )
    sizes = [len(b) for b in final_batches]
    total_tags = len(tags_for_tag_count(chosen, args.tag_prefix, args.implicit_tag))
    registry_reference_count = 2 if sign_registry_access_repos else 1
    print(
        f"chosen tag_count={chosen} signing_keys={len(signing_keys)} digests={len(digests)} "
        f"items={total_tags * len(signing_keys) * len(digests) * registry_reference_count} "
        f"batches={len(final_batches)} sizes={sizes}",
        file=sys.stderr,
    )
    if len(final_batches) != args.target_batches:
        print(
            f"error: final verification failed — expected {args.target_batches} batches, "
            f"got {len(final_batches)}",
            file=sys.stderr,
        )
        return 1

    print(chosen)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
