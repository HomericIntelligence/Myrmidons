#!/usr/bin/env bash
# scripts/package-dataset.sh — build a versioned dataset snapshot archive.
#
# Packages agents/, fleets/, schemas/ into dist/myrmidons-dataset-<version>.tar.gz
# together with a RELEASE_INFO manifest. Pure: reads the working tree, writes
# only dist/ (stale archives are removed first, so exactly one archive remains).
# Used by .github/workflows/release.yml, `just package`, and
# tests/unit/test_package_dataset.bats.
#
# Usage: package-dataset.sh [version]
#   version defaults to snapshot-<shortsha> of HEAD.
# Env:
#   PACKAGE_DATASET_ROOT — tree to package (default: this repo's root).
#                          Must be a git work tree containing agents/, fleets/,
#                          schemas/. Exists so bats tests can run against fixtures.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PACKAGE_DATASET_ROOT:-${REPO_ROOT}}"

version="${1:-snapshot-$(git rev-parse --short HEAD)}"

agent_count="$(find agents -name '*.yaml' ! -path '*/_templates/*' | wc -l)"
fleet_count="$(find fleets -name '*.yaml' | wc -l)"
if [[ "${agent_count}" -eq 0 || "${fleet_count}" -eq 0 ]]; then
    echo "ERROR: dataset looks empty (agents=${agent_count}, fleets=${fleet_count}); refusing to package." >&2
    exit 1
fi

mkdir -p dist
rm -f dist/myrmidons-dataset-*.tar.gz dist/RELEASE_INFO

{
    echo "version: ${version}"
    echo "commit: $(git rev-parse HEAD)"
    echo "commit-date: $(git log -1 --format=%cI)"
    echo "agents: ${agent_count}"
    echo "fleets: ${fleet_count}"
} > dist/RELEASE_INFO

archive="dist/myrmidons-dataset-${version}.tar.gz"
tar czf "${archive}" agents/ fleets/ schemas/ -C dist RELEASE_INFO

# Verify: list once into a variable (no tar|grep pipe — grep -q would exit at
# first match and SIGPIPE tar, exit 141 under pipefail), then assert contents.
contents="$(tar -tzf "${archive}")"
grep -q '^agents/' <<< "${contents}"
grep -q '^RELEASE_INFO$' <<< "${contents}"
echo "Packaged ${archive} (${agent_count} agents, ${fleet_count} fleets)"
