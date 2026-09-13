#!/bin/bash
# Install a checksum-pinned CI tool for the Debian image's native architecture.
# Release provenance and supported platforms are documented in CONTRIBUTING.md.
set -euo pipefail

tool="${1:?tool is required}"
destination="${2:?destination is required}"
architecture="$(dpkg --print-architecture)"
case "$architecture" in
    amd64|arm64) ;;
    *) echo "Unsupported CI tool architecture: $architecture" >&2; exit 1 ;;
esac

case "$tool:$architecture" in
    uv:amd64)
        repository=astral-sh/uv; version=0.12.1
        asset=uv-x86_64-unknown-linux-gnu.tar.gz
        checksum=90b2f223fb69d19db49e117da601f64978593417988530aa733d456141b4bcbb ;;
    uv:arm64)
        repository=astral-sh/uv; version=0.12.1
        asset=uv-aarch64-unknown-linux-gnu.tar.gz
        checksum=769d373e146692c639b5fbaae33b331c297a32e03d30448772051902df52bbf4 ;;
    just:amd64)
        repository=casey/just; version=1.58.0
        asset=just-1.58.0-x86_64-unknown-linux-musl.tar.gz
        checksum=4a5cc2f53e6f0f8c59092a6cc38291eb729d46a7dd95d3ae582008881b84931d ;;
    just:arm64)
        repository=casey/just; version=1.58.0
        asset=just-1.58.0-aarch64-unknown-linux-musl.tar.gz
        checksum=748237128c4c40cbdabc65e841d05ceba13cc23a91eaba395495894c1d9764df ;;
    yq:amd64)
        repository=mikefarah/yq; version=v4.44.3
        asset=yq_linux_amd64
        checksum=a2c097180dd884a8d50c956ee16a9cec070f30a7947cf4ebf87d5f36213e9ed7 ;;
    yq:arm64)
        repository=mikefarah/yq; version=v4.44.3
        asset=yq_linux_arm64
        checksum=0e7e1524f68d91b3ff9b089872d185940ab0fa020a5a9052046ef10547023156 ;;
    gitleaks:amd64)
        repository=gitleaks/gitleaks; version=v8.24.3
        asset=gitleaks_8.24.3_linux_x64.tar.gz
        checksum=9991e0b2903da4c8f6122b5c3186448b927a5da4deef1fe45271c3793f4ee29c ;;
    gitleaks:arm64)
        repository=gitleaks/gitleaks; version=v8.24.3
        asset=gitleaks_8.24.3_linux_arm64.tar.gz
        checksum=5f2edbe1f49f7b920f9e06e90759947d3c5dfc16f752fb93aaafc17e9d14cf07 ;;
    actionlint:amd64)
        repository=rhysd/actionlint; version=v1.7.7
        asset=actionlint_1.7.7_linux_amd64.tar.gz
        checksum=023070a287cd8cccd71515fedc843f1985bf96c436b7effaecce67290e7e0757 ;;
    actionlint:arm64)
        repository=rhysd/actionlint; version=v1.7.7
        asset=actionlint_1.7.7_linux_arm64.tar.gz
        checksum=401942f9c24ed71e4fe71b76c7d638f66d8633575c4016efd2977ce7c28317d0 ;;
    trivy:amd64)
        repository=aquasecurity/trivy; version=v0.70.0
        asset=trivy_0.70.0_Linux-64bit.tar.gz
        checksum=8b4376d5d6befe5c24d503f10ff136d9e0c49f9127a4279fd110b727929a5aa9 ;;
    trivy:arm64)
        repository=aquasecurity/trivy; version=v0.70.0
        asset=trivy_0.70.0_Linux-ARM64.tar.gz
        checksum=2f6bb988b553a1bbac6bdd1ce890f5e412439564e17522b88a4541b4f364fc8d ;;
    *) echo "Unsupported CI tool: $tool" >&2; exit 1 ;;
esac

archive_directory="$(mktemp -d)"
trap 'rm -rf -- "$archive_directory"' EXIT
archive="$archive_directory/$asset"
curl --fail --silent --show-error --location --retry 5 --retry-all-errors \
    --connect-timeout 15 --max-time 180 \
    "https://github.com/$repository/releases/download/$version/$asset" -o "$archive"
printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check
mkdir -p "$destination"
case "$tool" in
    uv)
        member_root="${asset%.tar.gz}"
        tar xzf "$archive" -C "$destination" --strip-components=1 \
            "$member_root/uv" "$member_root/uvx"
        ;;
    yq) install -m 0755 "$archive" "$destination/yq" ;;
    *) tar xzf "$archive" -C "$destination" "$tool" ;;
esac
