#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
policy="${ROOT}/configs/github/merge-queue-policy.json"
snapshot_dir=""

usage() {
    cat <<'EOF'
Usage: configure-merge-queue.sh [--policy PATH] --snapshot-dir DIRECTORY

Safely appends the repository merge-queue rule to the configured live ruleset.
The command fails closed on baseline drift and automatically restores the
durable pre-change snapshot if the post-PUT read-back fails validation.
EOF
}

while (($# > 0)); do
    case "$1" in
        --policy)
            policy="$2"
            shift 2
            ;;
        --snapshot-dir)
            snapshot_dir="$2"
            shift 2
            ;;
        --help | -h)
            usage
            exit 0
            ;;
        *)
            printf 'ERROR: unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

if [[ -z "$snapshot_dir" ]]; then
    printf 'ERROR: --snapshot-dir is required\n' >&2
    exit 64
fi
if [[ ! -r "$policy" ]]; then
    printf 'ERROR: policy is not readable: %s\n' "$policy" >&2
    exit 66
fi
for command in gh jq; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'ERROR: required command is missing: %s\n' "$command" >&2
        exit 69
    fi
done

if ! jq --exit-status '
    (.repository | type == "string" and length > 0) and
    (.ruleset_name | type == "string" and length > 0) and
    (.target_branch | type == "string" and length > 0) and
    (.required_contexts | type == "array" and length == 7 and
        length == (unique | length) and all(.[]; type == "string" and length > 0)) and
    (.merge_queue_rule.type == "merge_queue") and
    (.merge_queue_rule.parameters | type == "object")
' "$policy" >/dev/null; then
    printf 'ERROR: policy is malformed or does not contain seven unique contexts\n' >&2
    exit 65
fi

repo="$(jq --raw-output '.repository' "$policy")"
ruleset_name="$(jq --raw-output '.ruleset_name' "$policy")"
target_branch="$(jq --raw-output '.target_branch' "$policy")"
required_contexts="$(jq --compact-output '.required_contexts' "$policy")"
queue_rule="$(jq --compact-output '.merge_queue_rule' "$policy")"

assert_contract() {
    local ruleset_file="$1"
    local expect_queue="$2"

    jq --exit-status \
        --arg ruleset_name "$ruleset_name" \
        --arg target_ref "refs/heads/${target_branch}" \
        --argjson required_contexts "$required_contexts" \
        --argjson queue_rule "$queue_rule" \
        --argjson expect_queue "$expect_queue" '
        def status_rules:
            [.rules[] | select(.type == "required_status_checks")];
        def live_contexts:
            [status_rules[0].parameters.required_status_checks[].context];
        def queue_rules:
            [.rules[] | select(.type == "merge_queue")];

        .name == $ruleset_name and
        .target == "branch" and
        (.conditions.ref_name.include | index($target_ref)) != null and
        (status_rules | length) == 1 and
        (live_contexts | length) == ($required_contexts | length) and
        (live_contexts | sort) == ($required_contexts | sort) and
        queue_rules == (if $expect_queue then [$queue_rule] else [] end)
    ' "$ruleset_file" >/dev/null
}

assert_preserved() {
    local original="$1"
    local updated="$2"

    jq --exit-status --slurpfile original "$original" '
        .name == $original[0].name and
        .target == $original[0].target and
        .enforcement == $original[0].enforcement and
        .conditions == $original[0].conditions and
        (.bypass_actors // []) == ($original[0].bypass_actors // []) and
        ([.rules[] | select(.type != "merge_queue")] == $original[0].rules)
    ' "$updated" >/dev/null
}

to_put_payload() {
    local source_file="$1"
    local output_file="$2"

    jq '{name, target, enforcement, conditions,
         bypass_actors: (.bypass_actors // []), rules}' \
        "$source_file" > "$output_file"
}

mkdir -p "$snapshot_dir"
chmod 700 "$snapshot_dir"
umask 077

rulesets_file="$(mktemp "${snapshot_dir}/.rulesets.XXXXXX")"
candidate_file="$(mktemp "${snapshot_dir}/.candidate.XXXXXX")"
readback_file="$(mktemp "${snapshot_dir}/.readback.XXXXXX")"
restore_file="$(mktemp "${snapshot_dir}/.restore.XXXXXX")"
restore_response_file="$(mktemp "${snapshot_dir}/.restore-response.XXXXXX")"
snapshot_temp=""

cleanup_temporary_files() {
    rm -f "$rulesets_file" "$candidate_file" "$readback_file" \
        "$restore_file" "$restore_response_file"
    if [[ -n "$snapshot_temp" ]]; then
        rm -f "$snapshot_temp"
    fi
}
trap cleanup_temporary_files EXIT

gh api "repos/${repo}/rulesets" > "$rulesets_file"
ruleset_id="$(jq --exit-status --raw-output --arg name "$ruleset_name" '
    [.[] | select(.name == $name)]
    | if length == 1 then .[0].id else error("expected exactly one named ruleset") end
' "$rulesets_file")"

repo_name="${repo##*/}"
repo_name="${repo_name,,}"
snapshot="${snapshot_dir}/${repo_name}-ruleset-${ruleset_id}.json"
if [[ -e "$snapshot" ]]; then
    printf 'ERROR: refusing to overwrite retained snapshot: %s\n' "$snapshot" >&2
    exit 73
fi

snapshot_temp="${snapshot}.tmp"
gh api "repos/${repo}/rulesets/${ruleset_id}" > "$snapshot_temp"
jq empty "$snapshot_temp"
mv "$snapshot_temp" "$snapshot"
snapshot_temp=""

if ! assert_contract "$snapshot" false; then
    printf 'ERROR: live required contexts do not match policy or ruleset target drifted\n' >&2
    printf 'Snapshot retained: %s\n' "$snapshot" >&2
    exit 1
fi

jq --argjson queue_rule "$queue_rule" '
    {name, target, enforcement, conditions,
     bypass_actors: (.bypass_actors // []),
     rules: (.rules + [$queue_rule])}
' "$snapshot" > "$candidate_file"

if ! assert_contract "$candidate_file" true || \
    ! assert_preserved "$snapshot" "$candidate_file"; then
    printf 'ERROR: generated payload failed append/preservation assertions\n' >&2
    printf 'Snapshot retained: %s\n' "$snapshot" >&2
    exit 1
fi

rollback() {
    local reason="$1"

    printf 'ERROR: %s; restoring durable snapshot\n' "$reason" >&2
    to_put_payload "$snapshot" "$restore_file"
    if gh api --method PUT "repos/${repo}/rulesets/${ruleset_id}" \
        --input "$restore_file" > "$restore_response_file" && \
        assert_contract "$restore_response_file" false && \
        assert_preserved "$snapshot" "$restore_response_file"; then
        printf 'ERROR: restored pre-change ruleset; snapshot retained: %s\n' \
            "$snapshot" >&2
    else
        printf 'CRITICAL: automatic restoration could not be verified; snapshot retained: %s\n' \
            "$snapshot" >&2
    fi
    exit 1
}

if ! gh api --method PUT "repos/${repo}/rulesets/${ruleset_id}" \
    --input "$candidate_file" >/dev/null; then
    rollback "ruleset PUT failed or returned an ambiguous response"
fi

if ! gh api "repos/${repo}/rulesets/${ruleset_id}" > "$readback_file"; then
    rollback "post-PUT GET failed"
fi
if ! assert_contract "$readback_file" true; then
    rollback "post-PUT ruleset contract assertion failed"
fi
if ! assert_preserved "$snapshot" "$readback_file"; then
    rollback "post-PUT preservation assertion failed"
fi

rm -f "$snapshot"
printf 'Verified merge-queue activation for %s; deleted snapshot after successful read-back\n' \
    "$repo"
