#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# tests/unit/test_package_dataset.bats
#
# Issue #751: canonical `release` check. Verifies scripts/package-dataset.sh
# packages a dataset tree, refuses an empty dataset, honors an explicit
# version argument, and leaves exactly one archive after re-runs.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
PACKAGER="${SCRIPT_DIR}/scripts/package-dataset.sh"

TMP_DIR=""

setup() {
    TMP_DIR="$(mktemp -d)"
    mkdir -p "${TMP_DIR}/agents/hermes" "${TMP_DIR}/fleets" "${TMP_DIR}/schemas"
    echo "apiVersion: myrmidons/v1" > "${TMP_DIR}/agents/hermes/sample.yaml"
    echo "apiVersion: myrmidons/v1" > "${TMP_DIR}/fleets/sample.yaml"
    echo "{}" > "${TMP_DIR}/schemas/agent-v1.schema.json"
    git -C "${TMP_DIR}" init -q
    git -C "${TMP_DIR}" -c user.email=t@t -c user.name=t add -A
    git -C "${TMP_DIR}" -c user.email=t@t -c user.name=t commit -qm fixture
}

teardown() {
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
}

@test "package-dataset: happy path builds snapshot archive with manifest" {
    run env PACKAGE_DATASET_ROOT="$TMP_DIR" bash "$PACKAGER"
    [ "$status" -eq 0 ]
    sha="$(git -C "$TMP_DIR" rev-parse --short HEAD)"
    archive="${TMP_DIR}/dist/myrmidons-dataset-snapshot-${sha}.tar.gz"
    [ -f "$archive" ]
    tar -tzf "$archive" > "${TMP_DIR}/listing"
    grep -q '^agents/hermes/sample.yaml$' "${TMP_DIR}/listing"
    grep -q '^RELEASE_INFO$' "${TMP_DIR}/listing"
    grep -q "^version: snapshot-${sha}$" "${TMP_DIR}/dist/RELEASE_INFO"
}

@test "package-dataset: explicit version argument names archive and manifest" {
    run env PACKAGE_DATASET_ROOT="$TMP_DIR" bash "$PACKAGER" v1.2.3
    [ "$status" -eq 0 ]
    [ -f "${TMP_DIR}/dist/myrmidons-dataset-v1.2.3.tar.gz" ]
    grep -q '^version: v1.2.3$' "${TMP_DIR}/dist/RELEASE_INFO"
}

@test "package-dataset: empty dataset refused with exit 1" {
    rm "${TMP_DIR}/agents/hermes/sample.yaml"
    run env PACKAGE_DATASET_ROOT="$TMP_DIR" bash "$PACKAGER"
    [ "$status" -eq 1 ]
    [[ "$output" == *"refusing to package"* ]]
}

@test "package-dataset: re-run removes stale archives, exactly one remains" {
    run env PACKAGE_DATASET_ROOT="$TMP_DIR" bash "$PACKAGER" v1.0.0
    [ "$status" -eq 0 ]
    run env PACKAGE_DATASET_ROOT="$TMP_DIR" bash "$PACKAGER" v2.0.0
    [ "$status" -eq 0 ]
    count="$(find "${TMP_DIR}/dist" -name 'myrmidons-dataset-*.tar.gz' | wc -l)"
    [ "$count" -eq 1 ]
    [ -f "${TMP_DIR}/dist/myrmidons-dataset-v2.0.0.tar.gz" ]
}
