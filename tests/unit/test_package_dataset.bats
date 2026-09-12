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

@test "package-dataset: checksum binds the complete archive including pools" {
    mkdir "${TMP_DIR}/pools"
    echo "kind: ExecutionPool" > "${TMP_DIR}/pools/sample.yaml"
    run env PACKAGE_DATASET_ROOT="$TMP_DIR" bash "$PACKAGER" stable
    [ "$status" -eq 0 ]
    python3 - "${TMP_DIR}/dist" <<'PY'
import hashlib
from pathlib import Path
import sys
import tarfile

dist = Path(sys.argv[1])
archive = dist / "myrmidons-dataset-stable.tar.gz"
assert (dist / "SHA256SUMS").read_text() == f"{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n"
with tarfile.open(archive) as dataset:
    assert dataset.extractfile("pools/sample.yaml").read() == b"kind: ExecutionPool\n"
PY
}

@test "package-dataset: source timestamps do not change archive bytes" {
    run env PACKAGE_DATASET_ROOT="$TMP_DIR" bash "$PACKAGER" stable
    [ "$status" -eq 0 ]
    cp "${TMP_DIR}/dist/myrmidons-dataset-stable.tar.gz" "${TMP_DIR}/first.tar.gz"
    find "${TMP_DIR}/agents" "${TMP_DIR}/fleets" "${TMP_DIR}/schemas" -exec touch -t 200102030405 {} +
    run env PACKAGE_DATASET_ROOT="$TMP_DIR" bash "$PACKAGER" stable
    [ "$status" -eq 0 ]
    cmp "${TMP_DIR}/first.tar.gz" "${TMP_DIR}/dist/myrmidons-dataset-stable.tar.gz"
}

@test "package-dataset: archive owner and modification metadata are normalized" {
    run env PACKAGE_DATASET_ROOT="$TMP_DIR" bash "$PACKAGER" stable
    [ "$status" -eq 0 ]
    python3 - "${TMP_DIR}/dist/myrmidons-dataset-stable.tar.gz" <<'PY'
import sys
import tarfile

with tarfile.open(sys.argv[1]) as dataset:
    for member in dataset:
        assert (member.uid, member.gid, member.uname, member.gname) == (0, 0, "", "")
        assert member.mtime == 1577836800
PY
}

# Corrupt the real tar extraction at its process boundary. The archive itself
# remains readable, so listing members or checking its digest cannot detect this.
assert_roundtrip_rejects() {
    local target="$1" mutation="$2"
    mkdir "${TMP_DIR}/pools" "${TMP_DIR}/bin"
    echo "kind: ExecutionPool" > "${TMP_DIR}/pools/sample.yaml"
    cat > "${TMP_DIR}/bin/tar" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
"$REAL_TAR" "$@"
if [[ "$1" == "-xzf" ]]; then
    destination="$4/$TAMPER_TARGET"
    if [[ "$TAMPER_MODE" == "missing" ]]; then
        rm "$destination"
    else
        printf 'changed payload\n' > "$destination"
    fi
    touch "$TAMPER_MARKER"
fi
SH
    chmod +x "${TMP_DIR}/bin/tar"
    run env PATH="${TMP_DIR}/bin:$PATH" REAL_TAR="$(command -v tar)" \
        TAMPER_TARGET="$target" TAMPER_MODE="$mutation" TAMPER_MARKER="${TMP_DIR}/tampered" \
        PACKAGE_DATASET_ROOT="$TMP_DIR" bash "$PACKAGER" stable
    [ "$status" -ne 0 ]
    [ -f "${TMP_DIR}/tampered" ]
}

@test "package-dataset: rejects altered extracted agent" {
    assert_roundtrip_rejects agents/hermes/sample.yaml changed
}

@test "package-dataset: rejects missing extracted agent" {
    assert_roundtrip_rejects agents/hermes/sample.yaml missing
}

@test "package-dataset: rejects altered extracted fleet" {
    assert_roundtrip_rejects fleets/sample.yaml changed
}

@test "package-dataset: rejects missing extracted fleet" {
    assert_roundtrip_rejects fleets/sample.yaml missing
}

@test "package-dataset: rejects altered extracted schema" {
    assert_roundtrip_rejects schemas/agent-v1.schema.json changed
}

@test "package-dataset: rejects missing extracted schema" {
    assert_roundtrip_rejects schemas/agent-v1.schema.json missing
}

@test "package-dataset: rejects altered extracted pool" {
    assert_roundtrip_rejects pools/sample.yaml changed
}

@test "package-dataset: rejects missing extracted pool" {
    assert_roundtrip_rejects pools/sample.yaml missing
}

@test "package-dataset: checksum verification rejects a changed archive" {
    mkdir "${TMP_DIR}/bin"
    cat > "${TMP_DIR}/bin/sha256sum" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "-c" ]]; then
    printf 'corruption\n' >> myrmidons-dataset-stable.tar.gz
    touch "$TAMPER_MARKER"
fi
exec "$REAL_SHASUM" -a 256 "$@"
SH
    chmod +x "${TMP_DIR}/bin/sha256sum"
    run env PATH="${TMP_DIR}/bin:$PATH" REAL_SHASUM="$(command -v shasum)" \
        TAMPER_MARKER="${TMP_DIR}/tampered" PACKAGE_DATASET_ROOT="$TMP_DIR" \
        bash "$PACKAGER" stable
    [ "$status" -ne 0 ]
    [ -f "${TMP_DIR}/tampered" ]
}
