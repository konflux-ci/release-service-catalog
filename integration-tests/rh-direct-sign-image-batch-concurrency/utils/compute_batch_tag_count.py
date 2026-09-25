#!/usr/bin/env python3
"""compute_batch_tag_count.py - Compute the exact tag count that forces
rh_direct_sign_image.py's batch_signing_items() to split into a target
number of concurrently-submitted signing batches.

Rather than re-implementing rh_direct_sign_image.py's batching/item-collection
logic (which would silently drift from production as that script evolves),
this script imports and calls the real functions directly:
``collect_signing_items``, ``batch_signing_items``, ``get_all_image_digests``,
and ``get_signing_keys``. This guarantees the computed tag count matches
exactly what production will do -- including details easy to miss in a
reimplementation, such as multi-arch images contributing one signing item per
extra manifest digest, and the destination repository string being converted
from its quay.io temp-namespace form to its registry.redhat.io form (as
apply_mapping.py does) before being embedded in each signing reference.

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
      --tag-prefix batch-concur-abcd1234 \
      --batch-limit 15000 \
      --target-batches 2 \
      --margin 5

Prints the computed tag count to stdout. Diagnostics (resolved signing keys,
digests, batch sizes at the chosen count) are printed to stderr.
"""

from __future__ import annotations

import argparse
import sys

from release_service_utils.helpers.image_ref import convert_to_registry
from release_service_utils.helpers.kubectl import get_configmap
from rh_direct_sign_image import (
    batch_signing_items,
    collect_signing_items,
    get_all_image_digests,
    get_signing_keys,
)


def build_component(rh_registry_repo: str, tags: list[str]) -> dict:
    """Build the minimal post-apply_mapping component dict collect_signing_items() expects.

    Only ``repositories[].rh-registry-repo``/``tags`` are populated: no
    ``registry-access-repo`` (this test does not exercise the
    registry.access.redhat.com signing variant).
    """
    return {"repositories": [{"rh-registry-repo": rh_registry_repo, "tags": tags}]}


def batches_for_tag_count(
    num_tags: int,
    rh_registry_repo: str,
    digests: list[str],
    signing_keys: list[str],
    tag_prefix: str,
    batch_limit: int,
) -> list[str]:
    """Return the signing batches production would produce for ``num_tags`` tags."""
    tags = [f"{tag_prefix}-{i:04d}" for i in range(num_tags)]
    component = build_component(rh_registry_repo, tags)
    items = collect_signing_items(
        component,
        sign_registry_access_repos=set(),
        digests=digests,
        source_container_digest=None,
        signing_keys=signing_keys,
    )
    return batch_signing_items(items, max_batch_bytes=batch_limit)


def find_minimal_tag_count(
    rh_registry_repo: str,
    digests: list[str],
    signing_keys: list[str],
    tag_prefix: str,
    batch_limit: int,
    target_batches: int,
    upper_bound: int,
) -> int:
    """Find the smallest tag count that produces exactly target_batches batches."""
    for num_tags in range(1, upper_bound + 1):
        batch_count = len(
            batches_for_tag_count(
                num_tags,
                rh_registry_repo,
                digests,
                signing_keys,
                tag_prefix,
                batch_limit,
            )
        )
        if batch_count == target_batches:
            return num_tags
        if batch_count > target_batches:
            raise RuntimeError(
                f"Overshot target_batches={target_batches} at tags={num_tags} "
                f"(got {batch_count} batches) without ever hitting the target exactly. "
                "This can happen if a single item is larger than batch_limit, or if "
                "target_batches < len(signing_keys)*len(digests)-derived minimum. "
                "Check --batch-limit/the signing ConfigMap/the image's manifest list."
            )
    raise RuntimeError(
        f"Could not reach target_batches={target_batches} within upper_bound={upper_bound} tags"
    )


def find_tag_count_with_margin(
    rh_registry_repo: str,
    digests: list[str],
    signing_keys: list[str],
    tag_prefix: str,
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
        digests,
        signing_keys,
        tag_prefix,
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
                digests,
                signing_keys,
                tag_prefix,
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
        "--tag-prefix",
        required=True,
        help="Tag prefix; tags are '<prefix>-0000', '<prefix>-0001', ...",
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
    return parser.parse_args(argv)


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

    try:
        chosen = find_tag_count_with_margin(
            rh_registry_repo=rh_registry_repo,
            digests=digests,
            signing_keys=signing_keys,
            tag_prefix=args.tag_prefix,
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
        digests,
        signing_keys,
        args.tag_prefix,
        args.batch_limit,
    )
    sizes = [len(b) for b in final_batches]
    print(
        f"chosen tag_count={chosen} signing_keys={len(signing_keys)} digests={len(digests)} "
        f"items={chosen * len(signing_keys) * len(digests)} batches={len(final_batches)} sizes={sizes}",
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
