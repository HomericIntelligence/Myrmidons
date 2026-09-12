#!/usr/bin/env bash
# scripts/package-dataset.sh — build a versioned dataset snapshot archive.
#
# Packages agents/, fleets/, pools/ when present, and schemas/ into a dataset archive.
# together with a RELEASE_INFO manifest. Reads the working tree, writes dist/
# and a temporary verification directory removed on exit. Stale archives are
# removed first, so exactly one archive remains.
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
pool_count=0
dataset_paths=(agents/ fleets/ schemas/)
if [[ -d pools ]]; then
    pool_count="$(find pools -name '*.yaml' | wc -l)"
    dataset_paths+=(pools/)
fi
if [[ "${agent_count}" -eq 0 || "${fleet_count}" -eq 0 ]]; then
    echo "ERROR: dataset looks empty (agents=${agent_count}, fleets=${fleet_count}); refusing to package." >&2
    exit 1
fi

mkdir -p dist
rm -f dist/myrmidons-dataset-*.tar.gz dist/RELEASE_INFO dist/SHA256SUMS

{
    echo "version: ${version}"
    echo "commit: $(git rev-parse HEAD)"
    echo "commit-date: $(git log -1 --format=%cI)"
    echo "agents: ${agent_count}"
    echo "fleets: ${fleet_count}"
    echo "pools: ${pool_count}"
} > dist/RELEASE_INFO

archive="dist/myrmidons-dataset-${version}.tar.gz"
# Python's standard library gives macOS and Linux the same sorted archive and
# normalized metadata without requiring GNU tar on the laptop. Preserve source
# permissions and links; remove host ownership and wall-clock timestamps.
python3 - "${archive}" "${dataset_paths[@]}" <<'PY'
import gzip
import sys
import tarfile


def normalize(member: tarfile.TarInfo) -> tarfile.TarInfo:
    member.uid = member.gid = 0
    member.uname = member.gname = ""
    member.mtime = 1577836800  # 2020-01-01 UTC, matching the original CI contract
    member.pax_headers = {}
    return member


with open(sys.argv[1], "wb") as output:
    with gzip.GzipFile(filename="", mode="wb", fileobj=output, mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w") as dataset:
            for path in sys.argv[2:]:
                dataset.add(path, arcname=path, filter=normalize)
            dataset.add("dist/RELEASE_INFO", arcname="RELEASE_INFO", filter=normalize)
PY

if command -v sha256sum >/dev/null 2>&1; then
    checksum=(sha256sum)
else
    checksum=(shasum -a 256)
fi
(
    cd dist
    "${checksum[@]}" "${archive#dist/}" > SHA256SUMS
    "${checksum[@]}" -c SHA256SUMS
)

# Verify through the system tar reader and compare every extracted byte against
# the source, including optional pools and the release manifest. A valid gzip or
# member listing alone cannot establish that the complete dataset survived.
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
tar -xzf "${archive}" -C "${workdir}"
for path in "${dataset_paths[@]}"; do
    diff -r "${path}" "${workdir}/${path}"
done
cmp dist/RELEASE_INFO "${workdir}/RELEASE_INFO"
echo "Packaged ${archive} (${agent_count} agents, ${fleet_count} fleets, ${pool_count} pools)"
