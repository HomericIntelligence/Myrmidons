#!/usr/bin/env python3
"""check-changelog-gaps.py — detect conventional commits missing from CHANGELOG.md.

Scans git log since the last release tag for feat/fix/docs commits that have no
corresponding entry in the [Unreleased] section of CHANGELOG.md. Exits 1 if any
gaps are found so CI/pre-commit can block the PR.

Commits with `[skip changelog]` in their subject or body are exempt.

Usage:
    python scripts/check-changelog-gaps.py [--since <tag>] [--changelog <path>]
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


CHANGELOG_TYPES = frozenset({"feat", "fix", "docs"})


def find_last_tag() -> str | None:
    """Return the most recent release tag, or None if no tags exist."""
    result = subprocess.run(
        ["git", "describe", "--tags", "--abbrev=0"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def parse_prefix(subject: str) -> tuple[str | None, str | None, str]:
    """Extract (type, scope, description) from a conventional commit subject.

    Returns (None, None, subject) for non-conventional commits.
    """
    # Match: type(scope): description  or  type: description
    match = re.match(r"^([a-z]+)(?:\(([^)]+)\))?!?:\s*(.+)$", subject)
    if not match:
        return None, None, subject
    return match.group(1), match.group(2), match.group(3)


def get_commits_since(tag: str) -> list[tuple[str, str, str | None, str]]:
    """Return qualifying commits since `tag` as (hash, type, scope, description).

    Filters to CHANGELOG_TYPES only. Skips commits with `[skip changelog]` in subject.
    Uses tab-delimited output to avoid splitting on special characters in messages.
    """
    rev_range = f"{tag}..HEAD"
    result = subprocess.run(
        ["git", "log", rev_range, "--pretty=format:%h%x09%s", "--no-merges"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return []

    commits: list[tuple[str, str, str | None, str]] = []
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t", 1)
        if len(parts) != 2:
            continue
        short_hash, subject = parts[0], parts[1]

        if "[skip changelog]" in subject:
            continue

        commit_type, scope, description = parse_prefix(subject)
        if commit_type not in CHANGELOG_TYPES:
            continue

        commits.append((short_hash, commit_type, scope, description))

    return commits


def load_unreleased_entries(changelog_path: Path) -> set[str]:
    """Parse the [Unreleased] section and return a set of lowercased entry lines."""
    try:
        text = changelog_path.read_text(encoding="utf-8")
    except OSError:
        return set()

    entries: set[str] = set()
    in_unreleased = False
    for line in text.splitlines():
        if re.match(r"^##\s+\[Unreleased\]", line, re.IGNORECASE):
            in_unreleased = True
            continue
        if in_unreleased and re.match(r"^##\s+\[", line):
            break
        if in_unreleased and line.startswith("-"):
            entries.add(line.lower())

    return entries


def commit_is_covered(
    short_hash: str,
    description: str,
    entries: set[str],
) -> bool:
    """Return True if the commit appears to be documented in the [Unreleased] entries.

    Checks for the short hash or a normalized fragment of the description.
    """
    hash_lower = short_hash.lower()
    desc_lower = description.lower().strip()

    for entry in entries:
        if hash_lower in entry:
            return True
        # Check for a meaningful fragment (at least 20 chars) to reduce false positives
        if len(desc_lower) >= 20 and desc_lower[:20] in entry:
            return True
        if len(desc_lower) >= 10 and desc_lower[:10] in entry:
            return True

    return False


def main() -> int:
    """Orchestrate changelog gap detection. Returns exit code."""
    parser = argparse.ArgumentParser(
        description="Detect conventional commits missing from CHANGELOG.md [Unreleased]"
    )
    parser.add_argument(
        "--since",
        metavar="TAG",
        help="Check commits since this tag (default: last release tag)",
    )
    parser.add_argument(
        "--changelog",
        metavar="PATH",
        default=None,
        help="Path to CHANGELOG.md (default: CHANGELOG.md in repo root)",
    )
    args = parser.parse_args()

    # Resolve changelog path
    if args.changelog:
        changelog_path = Path(args.changelog)
    else:
        repo_root_result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
        )
        repo_root = Path(
            repo_root_result.stdout.strip() if repo_root_result.returncode == 0 else "."
        )
        changelog_path = repo_root / "CHANGELOG.md"

    # Determine the since-tag
    since_tag = args.since
    if not since_tag:
        since_tag = find_last_tag()

    if not since_tag:
        print(
            "check-changelog-gaps: WARNING: no release tag found; skipping check.",
            file=sys.stderr,
        )
        return 0

    # Load changelog entries once at init time
    entries = load_unreleased_entries(changelog_path)

    if not changelog_path.exists():
        print(
            f"check-changelog-gaps: ERROR: {changelog_path} not found.",
            file=sys.stderr,
        )
        return 1

    # Get qualifying commits
    commits = get_commits_since(since_tag)

    gaps: list[tuple[str, str, str | None, str]] = []
    for short_hash, commit_type, scope, description in commits:
        if not commit_is_covered(short_hash, description, entries):
            gaps.append((short_hash, commit_type, scope, description))

    if not gaps:
        print(
            f"check-changelog-gaps: OK — all {len(commits)} qualifying commit(s) "
            f"since {since_tag} are documented."
        )
        return 0

    print(
        f"check-changelog-gaps: ERROR — {len(gaps)} commit(s) since {since_tag} "
        f"have no corresponding [Unreleased] entry in {changelog_path}:",
        file=sys.stderr,
    )
    for short_hash, commit_type, scope, description in gaps:
        scope_str = f"({scope})" if scope else ""
        print(
            f"  {short_hash}  {commit_type}{scope_str}: {description}",
            file=sys.stderr,
        )
    print(
        "\nAdd entries to the [Unreleased] section of CHANGELOG.md, or include "
        "`[skip changelog]` in your commit subject to bypass this check.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
