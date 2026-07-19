#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    POLICY="${ROOT}/configs/github/merge-queue-policy.json"
    FIXTURE="${ROOT}/tests/fixtures/github/myrmidons-ruleset-before.json"
    WORKFLOW="${ROOT}/.github/workflows/_required.yml"
    SMOKE="${ROOT}/.github/workflows/merge-queue-smoke.yml"
    MUTATOR="${ROOT}/tools/github/configure-merge-queue.sh"
    FAKE_GH="${ROOT}/tests/fixtures/github/fake-gh.sh"
}

assert_main_only_scope() {
    jq --exit-status '
        .conditions.ref_name == {
            exclude: [],
            include: ["refs/heads/main"]
        }
    ' "$1" >/dev/null
}

@test "policy pins Myrmidons exact seven contexts and approved queue settings" {
    run jq --exit-status '
        .repository == "HomericIntelligence/Myrmidons" and
        .ruleset_name == "homeric-main-baseline" and
        .target_branch == "main" and
        .required_contexts == [
            "lint",
            "unit-tests",
            "security/dependency-scan",
            "security/secrets-scan",
            "build",
            "schema-validation",
            "deps/version-sync"
        ] and
        .merge_queue_rule == {
            type: "merge_queue",
            parameters: {
                merge_method: "SQUASH",
                grouping_strategy: "ALLGREEN",
                max_entries_to_build: 10,
                max_entries_to_merge: 5,
                min_entries_to_merge: 1,
                min_entries_to_merge_wait_minutes: 5,
                check_response_timeout_minutes: 60
            }
        }
    ' "$POLICY"

    [ "$status" -eq 0 ]
}

@test "required checks workflow no longer runs on merge-group events" {
    run yq eval --exit-status '.on | has("merge_group") | not' "$WORKFLOW"

    [ "$status" -eq 0 ]
}

@test "merge-queue smoke workflow handles merge-group checks_requested events only" {
    run yq eval --exit-status '
        (.on | keys | length) == 1 and
        (.on | keys | .[0]) == "merge_group" and
        (.on.merge_group.types | length) == 1 and
        .on.merge_group.types[0] == "checks_requested"
    ' "$SMOKE"

    [ "$status" -eq 0 ]
}

@test "merge-queue smoke workflow runs exactly one fast job named merge-queue-smoke" {
    run yq eval --exit-status '
        (.jobs | keys | length) == 1 and
        (.jobs | keys | .[0]) == "merge-queue-smoke" and
        .jobs."merge-queue-smoke".name == "merge-queue-smoke" and
        .jobs."merge-queue-smoke".timeout-minutes == 5
    ' "$SMOKE"

    [ "$status" -eq 0 ]
}

@test "required checks workflow preserves pull-request and push main triggers" {
    run yq eval --exit-status '
        (.on.pull_request.branches | length) == 1 and
        .on.pull_request.branches[0] == "main" and
        (.on.push.branches | length) == 1 and
        .on.push.branches[0] == "main"
    ' "$WORKFLOW"

    [ "$status" -eq 0 ]
}

@test "required checks workflow supplies every context in repository policy" {
    while IFS= read -r context; do
        run yq eval --exit-status ".jobs[] | select(.name == \"${context}\") | .name" \
            "$WORKFLOW"

        [ "$status" -eq 0 ]
    done < <(jq --raw-output '.required_contexts[]' "$POLICY")
}

@test "ruleset fixture targets exactly refs/heads/main with no exclusions" {
    run assert_main_only_scope "$FIXTURE"

    [ "$status" -eq 0 ]
}

@test "ruleset contract rejects an additional included ref" {
    drifted="${BATS_TEST_TMPDIR}/extra-include.json"
    jq '.conditions.ref_name.include += ["refs/heads/release"]' \
        "$FIXTURE" > "$drifted"

    run assert_main_only_scope "$drifted"

    [ "$status" -ne 0 ]
}

@test "ruleset contract rejects any excluded ref" {
    drifted="${BATS_TEST_TMPDIR}/excluded-ref.json"
    jq '.conditions.ref_name.exclude += ["refs/heads/emergency"]' \
        "$FIXTURE" > "$drifted"

    run assert_main_only_scope "$drifted"

    [ "$status" -ne 0 ]
}

@test "ruleset fixture preserves the exact live repository-role bypass actor" {
    run jq --exit-status '
        .bypass_actors == [{
            actor_id: 5,
            actor_type: "RepositoryRole",
            bypass_mode: "pull_request"
        }]
    ' "$FIXTURE"

    [ "$status" -eq 0 ]
}

@test "ruleset fixture pins the exact seven required contexts" {
    run jq --exit-status --slurpfile policy "$POLICY" '
        [.rules[] | select(.type == "required_status_checks")
            | .parameters.required_status_checks[].context]
        == $policy[0].required_contexts
    ' "$FIXTURE"

    [ "$status" -eq 0 ]
}

@test "offline Odysseus activation candidate preserves bypass actor and unrelated rules" {
    candidate="${BATS_TEST_TMPDIR}/candidate.json"
    jq --slurpfile policy "$POLICY" \
        '.rules += [$policy[0].merge_queue_rule]' \
        "$FIXTURE" > "$candidate"

    run jq --exit-status --slurpfile before "$FIXTURE" \
        --slurpfile policy "$POLICY" '
        .name == $before[0].name and
        .target == $before[0].target and
        .enforcement == $before[0].enforcement and
        .conditions == $before[0].conditions and
        .bypass_actors == $before[0].bypass_actors and
        ([.rules[] | select(.type != "merge_queue")] == $before[0].rules) and
        ([.rules[] | select(.type == "merge_queue")] == [$policy[0].merge_queue_rule])
    ' "$candidate"

    [ "$status" -eq 0 ]
}

@test "dataset repository contains no merge-queue API mutator or fake API harness" {
    [ ! -e "$MUTATOR" ]
    [ ! -e "$FAKE_GH" ]
}
