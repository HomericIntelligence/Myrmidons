#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    SCRIPT="${ROOT}/tools/github/configure-merge-queue.sh"
    POLICY="${ROOT}/configs/github/merge-queue-policy.json"
    FIXTURE="${ROOT}/tests/fixtures/github/myrmidons-ruleset-before.json"
    WORKFLOW="${ROOT}/.github/workflows/_required.yml"

    export FAKE_LOG_DIR="${BATS_TEST_TMPDIR}/gh-log"
    export FAKE_LIVE_RULESET="${BATS_TEST_TMPDIR}/live-ruleset.json"
    export FAKE_PUT_COUNT_FILE="${BATS_TEST_TMPDIR}/put-count"
    SNAPSHOT_DIR="${BATS_TEST_TMPDIR}/snapshots"
    fake_bin="${BATS_TEST_TMPDIR}/bin"

    mkdir -p "$FAKE_LOG_DIR" "$SNAPSHOT_DIR" "$fake_bin"
    cp "$FIXTURE" "$FAKE_LIVE_RULESET"
    cp "${ROOT}/tests/fixtures/github/fake-gh.sh" "${fake_bin}/gh"
    chmod +x "${fake_bin}/gh"
    printf '0\n' > "$FAKE_PUT_COUNT_FILE"
    export PATH="${fake_bin}:${PATH}"
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

@test "required checks workflow handles merge-group checks_requested events" {
    run yq eval --exit-status '
        (.on.merge_group.types | length) == 1 and
        .on.merge_group.types[0] == "checks_requested"
    ' "$WORKFLOW"

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

@test "activation appends queue policy and preserves every unrelated protection" {
    run "$SCRIPT" --policy "$POLICY" --snapshot-dir "$SNAPSHOT_DIR"

    [ "$status" -eq 0 ]
    [ "$(<"$FAKE_PUT_COUNT_FILE")" -eq 1 ]
    [ ! -e "$SNAPSHOT_DIR/myrmidons-ruleset-15556489.json" ]

    run jq --exit-status --slurpfile before "$FIXTURE" --slurpfile policy "$POLICY" '
        .name == $before[0].name and
        .target == $before[0].target and
        .enforcement == $before[0].enforcement and
        .conditions == $before[0].conditions and
        .bypass_actors == [] and
        ([.rules[] | select(.type != "merge_queue")] == $before[0].rules) and
        ([.rules[] | select(.type == "merge_queue")] == [$policy[0].merge_queue_rule])
    ' "$FAKE_LOG_DIR/put-1.json"

    [ "$status" -eq 0 ]
}

@test "activation refuses context drift before PUT and retains its snapshot" {
    jq '(.rules[] | select(.type == "required_status_checks")
        | .parameters.required_status_checks) |= map(select(.context != "lint"))' \
        "$FIXTURE" > "${BATS_TEST_TMPDIR}/drifted.json"
    cp "${BATS_TEST_TMPDIR}/drifted.json" "$FAKE_LIVE_RULESET"

    run "$SCRIPT" --policy "$POLICY" --snapshot-dir "$SNAPSHOT_DIR"

    [ "$status" -ne 0 ]
    [ "$(<"$FAKE_PUT_COUNT_FILE")" -eq 0 ]
    [ -s "$SNAPSHOT_DIR/myrmidons-ruleset-15556489.json" ]
    [[ "$output" == *"required contexts do not match policy"* ]]
}

@test "post-PUT GET failure automatically restores and retains durable snapshot" {
    export FAKE_FAIL_POST_PUT_GET=1

    run "$SCRIPT" --policy "$POLICY" --snapshot-dir "$SNAPSHOT_DIR"

    [ "$status" -ne 0 ]
    [ "$(<"$FAKE_PUT_COUNT_FILE")" -eq 2 ]
    [ -s "$SNAPSHOT_DIR/myrmidons-ruleset-15556489.json" ]
    [[ "$output" == *"restored pre-change ruleset"* ]]

    run jq --exit-status --slurpfile before "$FIXTURE" '
        .name == $before[0].name and
        .target == $before[0].target and
        .enforcement == $before[0].enforcement and
        .conditions == $before[0].conditions and
        .bypass_actors == [] and
        .rules == $before[0].rules
    ' "$FAKE_LOG_DIR/put-2.json"

    [ "$status" -eq 0 ]
}

@test "ambiguous PUT failure automatically restores the durable snapshot" {
    export FAKE_FAIL_FIRST_PUT_AFTER_APPLY=1

    run "$SCRIPT" --policy "$POLICY" --snapshot-dir "$SNAPSHOT_DIR"

    [ "$status" -ne 0 ]
    [ "$(<"$FAKE_PUT_COUNT_FILE")" -eq 2 ]
    [ -s "$SNAPSHOT_DIR/myrmidons-ruleset-15556489.json" ]
    [[ "$output" == *"restored pre-change ruleset"* ]]

    run jq --exit-status --slurpfile before "$FIXTURE" '.rules == $before[0].rules' \
        "$FAKE_LOG_DIR/put-2.json"

    [ "$status" -eq 0 ]
}

@test "failed read-back assertions automatically restore original protections" {
    export FAKE_TAMPER_FIRST_PUT=1

    run "$SCRIPT" --policy "$POLICY" --snapshot-dir "$SNAPSHOT_DIR"

    [ "$status" -ne 0 ]
    [ "$(<"$FAKE_PUT_COUNT_FILE")" -eq 2 ]
    [ -s "$SNAPSHOT_DIR/myrmidons-ruleset-15556489.json" ]
    [[ "$output" == *"restored pre-change ruleset"* ]]

    run jq --exit-status --slurpfile before "$FIXTURE" '.rules == $before[0].rules' \
        "$FAKE_LOG_DIR/put-2.json"

    [ "$status" -eq 0 ]
}
