#!/usr/bin/env bats
# Regression coverage for the repository-owned half of merge-queue readiness.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
WORKFLOW="${SCRIPT_DIR}/.github/workflows/_required.yml"

@test "required checks workflow handles merge-group checks_requested events" {
    run yq eval --exit-status \
        '(.on.merge_group.types | length) == 1 and
         .on.merge_group.types[0] == "checks_requested"' \
        "$WORKFLOW"

    [ "$status" -eq 0 ]
}

@test "required checks workflow preserves pull-request and push main triggers" {
    run yq eval --exit-status \
        '(.on.pull_request.branches | length) == 1 and
         .on.pull_request.branches[0] == "main" and
         (.on.push.branches | length) == 1 and
         .on.push.branches[0] == "main"' \
        "$WORKFLOW"

    [ "$status" -eq 0 ]
}

@test "required checks workflow supplies every live required context" {
    # Captured from the active homeric-main-baseline ruleset on 2026-07-16.
    local required_contexts=(
        "lint"
        "unit-tests"
        "security/dependency-scan"
        "security/secrets-scan"
        "build"
        "schema-validation"
        "deps/version-sync"
    )
    local context

    for context in "${required_contexts[@]}"; do
        run yq eval --exit-status \
            ".jobs[] | select(.name == \"${context}\") | .name" \
            "$WORKFLOW"

        [ "$status" -eq 0 ]
    done
}
