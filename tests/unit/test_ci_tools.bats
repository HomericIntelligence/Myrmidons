#!/usr/bin/env bats
# Exercise the installer process with controlled OS and release-download boundaries.
# Successful digest/extraction acknowledgments are fixtures; mismatch uses real SHA-256.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    MOCK_ROOT=$(mktemp -d)
    export MOCK_ROOT
    mkdir -p "$MOCK_ROOT/bin" "$MOCK_ROOT/tmp"
    export TOOL_CALLS="$MOCK_ROOT/calls"
    export TMPDIR="$MOCK_ROOT/tmp"
    export TOOL_ARCH=arm64
    export TOOL_PYTHON
    TOOL_PYTHON=$(command -v python3)
    cat > "$MOCK_ROOT/bin/tool-fixture" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
name=${0##*/}
printf '%s %s\n' "$name" "$*" >> "$TOOL_CALLS"
case "$name" in
    dpkg)
        [[ "$*" == --print-architecture ]]
        printf '%s\n' "$TOOL_ARCH"
        ;;
    curl)
        [[ "${DOWNLOAD_FAILURE:-0}" != 1 ]] || exit 47
        while [[ "$1" != -o ]]; do shift; done
        if [[ "${IMAGE_STAGE:-0}" == 1 ]]; then
            printf 'controlled downloaded bytes\n' > "$TMPDIR/image-download"
        else
            printf 'controlled downloaded bytes\n' > "$2"
        fi
        ;;
    sha256sum)
        read -r digest archive
        printf 'checksum %s %s\n' "$digest" "$archive" >> "$TOOL_CALLS"
        if [[ "${REAL_CHECKSUM:-0}" == 1 ]]; then
            "$TOOL_PYTHON" - "$digest" "$archive" <<'PY'
import hashlib, pathlib, sys
actual = hashlib.sha256(pathlib.Path(sys.argv[2]).read_bytes()).hexdigest()
sys.exit(0 if actual == sys.argv[1] else 1)
PY
        fi
        ;;
    tar)
        [[ "${EXTRACTION_FAILURE:-0}" != 1 ]] || exit 48
        ;;
    apt-get) ;;
    rm)
        if [[ "${IMAGE_STAGE:-0}" != 1 ]]; then
            exec /bin/rm "$@"
        fi
        ;;
esac
SCRIPT
    chmod +x "$MOCK_ROOT/bin/tool-fixture"
    for command in dpkg curl sha256sum tar apt-get rm; do
        ln -s tool-fixture "$MOCK_ROOT/bin/$command"
    done
    export PATH="$MOCK_ROOT/bin:$PATH"
}

teardown() {
    /bin/rm -rf "$MOCK_ROOT"
}

@test "the image uv installation stage selects the native arm64 release" {
    # Execute the real RUN instruction. Only the container's package/filesystem/
    # download boundaries are inert substitutes; no engine or host system write.
    local step
    step=$("$TOOL_PYTHON" - "$REPO_ROOT" "$MOCK_ROOT" <<'PY'
import pathlib, shlex, sys
root = pathlib.Path(sys.argv[1])
text = (root / "ci/Containerfile").read_text().replace("\\\n", " ")
steps = [line[4:] for line in text.splitlines() if line.startswith("RUN ")]
matches = [line for line in steps if "uv/releases/download/" in line or "install-tool.sh uv " in line]
assert len(matches) == 1, matches
step = matches[0].replace("/opt/ci/install-tool.sh", shlex.quote(str(root / "ci/install-tool.sh")))
print(step.replace("/usr/local/bin", shlex.quote(str(pathlib.Path(sys.argv[2]) / "image-bin"))))
PY
    )
    export IMAGE_STAGE=1
    run bash -c "$step"
    [ "$status" -eq 0 ]
    grep -F '/uv-aarch64-unknown-linux-gnu.tar.gz -o ' "$TOOL_CALLS"
    run grep -F '/uv-x86_64-unknown-linux-gnu.tar.gz -o ' "$TOOL_CALLS"
    [ "$status" -eq 1 ]
}

check_asset() {
    local tool=$1 asset=$2 digest=$3
    : > "$TOOL_CALLS"
    run bash "$REPO_ROOT/ci/install-tool.sh" "$tool" "$MOCK_ROOT/destination with spaces"
    [ "$status" -eq 0 ]
    grep -F "/$asset -o " "$TOOL_CALLS"
    grep -F "checksum $digest " "$TOOL_CALLS"
    # Verification must complete before tar extraction; raw yq uses install instead.
    if [[ "$tool" == yq ]]; then
        cmp "$MOCK_ROOT/destination with spaces/yq" <(printf 'controlled downloaded bytes\n')
        [ -x "$MOCK_ROOT/destination with spaces/yq" ]
    else
        local checksum_line extract_line
        checksum_line=$(grep -n '^checksum ' "$TOOL_CALLS" | cut -d: -f1)
        extract_line=$(grep -n '^tar ' "$TOOL_CALLS" | cut -d: -f1)
        [ "$checksum_line" -lt "$extract_line" ]
        if [[ "$tool" == uv ]]; then
            grep -F -- '--strip-components=1 uv-' "$TOOL_CALLS"
            grep -F '/uvx' "$TOOL_CALLS"
        else
            grep -E "^tar .* $tool$" "$TOOL_CALLS"
        fi
    fi
    [ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]
}

@test "native arm64 installs the existing six tool versions with architecture-specific pins" {
    check_asset uv uv-aarch64-unknown-linux-gnu.tar.gz 769d373e146692c639b5fbaae33b331c297a32e03d30448772051902df52bbf4
    check_asset just just-1.58.0-aarch64-unknown-linux-musl.tar.gz 748237128c4c40cbdabc65e841d05ceba13cc23a91eaba395495894c1d9764df
    check_asset yq yq_linux_arm64 0e7e1524f68d91b3ff9b089872d185940ab0fa020a5a9052046ef10547023156
    check_asset gitleaks gitleaks_8.24.3_linux_arm64.tar.gz 5f2edbe1f49f7b920f9e06e90759947d3c5dfc16f752fb93aaafc17e9d14cf07
    check_asset actionlint actionlint_1.7.7_linux_arm64.tar.gz 401942f9c24ed71e4fe71b76c7d638f66d8633575c4016efd2977ce7c28317d0
    check_asset trivy trivy_0.70.0_Linux-ARM64.tar.gz 2f6bb988b553a1bbac6bdd1ce890f5e412439564e17522b88a4541b4f364fc8d
}

@test "native amd64 retains every existing release and checksum" {
    export TOOL_ARCH=amd64
    check_asset uv uv-x86_64-unknown-linux-gnu.tar.gz 90b2f223fb69d19db49e117da601f64978593417988530aa733d456141b4bcbb
    check_asset just just-1.58.0-x86_64-unknown-linux-musl.tar.gz 4a5cc2f53e6f0f8c59092a6cc38291eb729d46a7dd95d3ae582008881b84931d
    check_asset yq yq_linux_amd64 a2c097180dd884a8d50c956ee16a9cec070f30a7947cf4ebf87d5f36213e9ed7
    check_asset gitleaks gitleaks_8.24.3_linux_x64.tar.gz 9991e0b2903da4c8f6122b5c3186448b927a5da4deef1fe45271c3793f4ee29c
    check_asset actionlint actionlint_1.7.7_linux_amd64.tar.gz 023070a287cd8cccd71515fedc843f1985bf96c436b7effaecce67290e7e0757
    check_asset trivy trivy_0.70.0_Linux-64bit.tar.gz 8b4376d5d6befe5c24d503f10ff136d9e0c49f9127a4279fd110b727929a5aa9
}

@test "unknown native architectures fail before downloading" {
    export TOOL_ARCH=riscv64
    run bash "$REPO_ROOT/ci/install-tool.sh" uv "$MOCK_ROOT/destination"
    [ "$status" -ne 0 ]
    [[ "$output" == *'Unsupported CI tool architecture: riscv64'* ]]
    run grep -Eq '^(curl|tar|sha256sum) ' "$TOOL_CALLS"
    [ "$status" -eq 1 ]
    [ ! -e "$MOCK_ROOT/destination" ]
}

@test "unknown tools fail before downloading" {
    run bash "$REPO_ROOT/ci/install-tool.sh" unknown "$MOCK_ROOT/destination"
    [ "$status" -ne 0 ]
    [[ "$output" == *'Unsupported CI tool: unknown'* ]]
    run grep -Eq '^(curl|tar|sha256sum) ' "$TOOL_CALLS"
    [ "$status" -eq 1 ]
    [ ! -e "$MOCK_ROOT/destination" ]
}

@test "download failure stops before checksum or installation and removes temporary files" {
    export DOWNLOAD_FAILURE=1
    run bash "$REPO_ROOT/ci/install-tool.sh" uv "$MOCK_ROOT/destination"
    [ "$status" -eq 47 ]
    run grep -Eq '^(tar|sha256sum) ' "$TOOL_CALLS"
    [ "$status" -eq 1 ]
    [ ! -e "$MOCK_ROOT/destination" ]
    [ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]
}

@test "real SHA-256 mismatch rejects archive and raw binary before destination writes" {
    export REAL_CHECKSUM=1
    for tool in uv yq; do
        : > "$TOOL_CALLS"
        run bash "$REPO_ROOT/ci/install-tool.sh" "$tool" "$MOCK_ROOT/destination"
        [ "$status" -ne 0 ]
        grep -q '^checksum ' "$TOOL_CALLS"
        run grep -q '^tar ' "$TOOL_CALLS"
        [ "$status" -eq 1 ]
        [ ! -e "$MOCK_ROOT/destination" ]
        [ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]
    done
}

@test "extraction failure is retained and temporary download is removed" {
    export EXTRACTION_FAILURE=1
    run bash "$REPO_ROOT/ci/install-tool.sh" just "$MOCK_ROOT/destination"
    [ "$status" -eq 48 ]
    grep -q '^checksum ' "$TOOL_CALLS"
    [ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]
}
