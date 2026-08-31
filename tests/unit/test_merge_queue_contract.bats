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

assert_required_contexts_unconditional() {
    workflow="$1"

    while IFS= read -r context; do
        count="$(yq eval "[.jobs[] | select(.name == \"${context}\")] | length" "$workflow")"
        [ "$count" -eq 1 ] || return 1

        yq eval --exit-status ".jobs[] | select(.name == \"${context}\") | has(\"if\") | not" \
            "$workflow" >/dev/null || return 1
        yq eval --exit-status ".jobs[] | select(.name == \"${context}\") | has(\"needs\") | not" \
            "$workflow" >/dev/null || return 1
    done < <(jq --raw-output '.required_contexts[]' "$POLICY")
}

render_required_concurrency_group() {
    workflow_name="$1"
    event_name="$2"
    pull_request_number="$3"
    sha="$4"
    head_ref="$5"
    template="$(yq eval '.concurrency.group' "$WORKFLOW")"

    case "$template" in
        '${{ github.workflow }}-${{ github.event_name }}-${{ github.event.pull_request.number || github.sha }}')
            identity="${pull_request_number:-$sha}"
            printf '%s-%s-%s\n' "$workflow_name" "$event_name" "$identity"
            ;;
        'required-${{ github.event_name }}-${{ github.head_ref || github.sha }}')
            identity="${head_ref:-$sha}"
            printf 'required-%s-%s\n' "$event_name" "$identity"
            ;;
        *)
            return 1
            ;;
    esac
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

@test "required checks workflow has exact pull-request push and merge-group triggers" {
    run yq eval --exit-status '
        (.on | keys | length) == 3 and
        (.on | has("pull_request")) and
        (.on.pull_request.branches | length) == 1 and
        .on.pull_request.branches[0] == "main" and
        (.on | has("push")) and
        (.on.push.branches | length) == 1 and
        .on.push.branches[0] == "main" and
        (.on | has("merge_group")) and
        (.on.merge_group | keys | length) == 1 and
        (.on.merge_group.types | length) == 1 and
        .on.merge_group.types[0] == "checks_requested"
    ' "$WORKFLOW"

    [ "$status" -eq 0 ]
}

@test "required checks concurrency uses workflow event and pull-request-or-sha identity" {
    expected_group="\${{ github.workflow }}-\${{ github.event_name }}-\${{ github.event.pull_request.number || github.sha }}"
    run env EXPECTED_GROUP="$expected_group" yq eval --exit-status '
        .concurrency.group == strenv(EXPECTED_GROUP) and
        .concurrency.cancel-in-progress == true
    ' "$WORKFLOW"

    [ "$status" -eq 0 ]
}

@test "concurrency distinguishes fork pull requests with identical source branches" {
    first="$(render_required_concurrency_group 'Required Checks' pull_request 101 first-sha renovate/deps)"
    second="$(render_required_concurrency_group 'Required Checks' pull_request 202 second-sha renovate/deps)"

    [ "$first" != "$second" ]
}

@test "concurrency cancels a stale run for the same pull request" {
    first="$(render_required_concurrency_group 'Required Checks' pull_request 101 first-sha feature/example)"
    second="$(render_required_concurrency_group 'Required Checks' pull_request 101 second-sha feature/example)"

    [ "$first" = "$second" ]
}

@test "concurrency separates pull-request and merge-group runs" {
    pull_request="$(render_required_concurrency_group 'Required Checks' pull_request 101 shared-sha feature/example)"
    merge_group="$(render_required_concurrency_group 'Required Checks' merge_group '' shared-sha '')"

    [ "$pull_request" != "$merge_group" ]
}

@test "smoke-only merge-group carrier is absent" {
    [ ! -e "$SMOKE" ]

    run grep --fixed-strings --recursive --line-number --include='*.yml' --include='*.yaml' \
        'merge-queue-smoke' "${ROOT}/.github/workflows"

    [ "$status" -eq 1 ]
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
    run assert_required_contexts_unconditional "$WORKFLOW"

    [ "$status" -eq 0 ]
}

@test "required context contract rejects an event-suppressed job" {
    drifted="${BATS_TEST_TMPDIR}/event-suppressed.yml"
    yq eval '.jobs.lint.if = "github.event_name != '\''merge_group'\''"' \
        "$WORKFLOW" > "$drifted"

    run assert_required_contexts_unconditional "$drifted"

    [ "$status" -ne 0 ]
}

@test "required context contract rejects a dependent producer" {
    drifted="${BATS_TEST_TMPDIR}/dependent-producer.yml"
    yq eval '.jobs.lint.needs = "typecheck"' "$WORKFLOW" > "$drifted"

    run assert_required_contexts_unconditional "$drifted"

    [ "$status" -ne 0 ]
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
