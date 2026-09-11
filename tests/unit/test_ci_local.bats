#!/usr/bin/env bats
# CI launcher contracts with an inert engine and disposable command fixtures.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    MOCK_ROOT=$(mktemp -d)
    export MOCK_ROOT
    mkdir -p "$MOCK_ROOT/bin" "$MOCK_ROOT/scripts"
    printf '# fixture\n' > "$MOCK_ROOT/scripts/example.py"
    export CI_CALLS="$MOCK_ROOT/calls"
    cat > "$MOCK_ROOT/bin/command-fixture" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
name=${0##*/}
if [[ "$name" == engine ]]; then
    [[ "$1" != run ]] && exit 0
    while [[ "$1" != myrmidons-ci:local ]]; do shift; done
    shift
    if [[ "${CI_CAPTURE_ONLY:-0}" == 1 ]]; then
        printf '%s\n' "$*" > "$CI_CALLS"
        exit 0
    fi
    cd "$MOCK_ROOT"
    exec "$@"
fi
printf '%s %s\n' "$name" "$*" >> "$CI_CALLS"
case "$name" in
    git) printf 'scripts/example.py\n' ;;
    uv)
        [[ "${1:-}" == sync ]] && exit 0
        exit "${UV_RESULT:-0}"
        ;;
    trivy)
        exit "${TRIVY_RESULT:-0}"
        ;;
    just|gitleaks) exit 0 ;;
esac
SCRIPT
    chmod +x "$MOCK_ROOT/bin/command-fixture"
    for command in engine uv trivy just gitleaks git; do
        ln -s command-fixture "$MOCK_ROOT/bin/$command"
    done
    export PATH="$MOCK_ROOT/bin:$PATH"
    export CONTAINER_ENGINE="$MOCK_ROOT/bin/engine"
}

teardown() {
    rm -rf "$MOCK_ROOT"
}

@test "local CI unit step includes pool contracts" {
    export CI_CAPTURE_ONLY=1
    run bash "$REPO_ROOT/scripts/run_ci_local.sh" test
    [ "$status" -eq 0 ]
    grep -qx 'just test-unit test-pools' "$CI_CALLS"
}

@test "local CI packaging uses the canonical dataset recipe" {
    export CI_CAPTURE_ONLY=1
    run bash "$REPO_ROOT/scripts/run_ci_local.sh" package
    [ "$status" -eq 0 ]
    grep -qx 'just package' "$CI_CALLS"
}

@test "local CI typecheck propagates dependency or analyzer failure" {
    export UV_RESULT=47
    run bash "$REPO_ROOT/scripts/run_ci_local.sh" typecheck
    [ "$status" -ne 0 ]
    [[ "$output" == *"typecheck FAILED"* ]]
}

@test "local CI security propagates audit failure" {
    export UV_RESULT=47
    run bash "$REPO_ROOT/scripts/run_ci_local.sh" security
    [ "$status" -ne 0 ]
    [[ "$output" == *"security FAILED"* ]]
}

@test "local CI security propagates scanner execution failure" {
    export TRIVY_RESULT=47
    run bash "$REPO_ROOT/scripts/run_ci_local.sh" security
    [ "$status" -ne 0 ]
    [[ "$output" == *"security FAILED"* ]]
}
