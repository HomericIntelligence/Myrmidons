#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "api" ]]; then
    printf 'fake gh only supports the api command\n' >&2
    exit 64
fi
shift

method="GET"
input=""
endpoint=""

while (($# > 0)); do
    case "$1" in
        --method | -X)
            method="$2"
            shift 2
            ;;
        --input)
            input="$2"
            shift 2
            ;;
        --jq)
            shift 2
            ;;
        -*)
            printf 'unsupported fake gh option: %s\n' "$1" >&2
            exit 64
            ;;
        *)
            endpoint="$1"
            shift
            ;;
    esac
done

repo_endpoint="repos/HomericIntelligence/Myrmidons/rulesets"
ruleset_endpoint="${repo_endpoint}/15556489"

if [[ "$method" == "GET" && "$endpoint" == "$repo_endpoint" ]]; then
    printf '[{"id":15556489,"name":"homeric-main-baseline"}]\n'
    exit 0
fi

if [[ "$endpoint" != "$ruleset_endpoint" ]]; then
    printf 'unexpected endpoint: %s\n' "$endpoint" >&2
    exit 64
fi

put_count="$(<"$FAKE_PUT_COUNT_FILE")"
if [[ "$method" == "GET" ]]; then
    if [[ "${FAKE_FAIL_POST_PUT_GET:-0}" == "1" && "$put_count" == "1" ]]; then
        printf 'simulated post-PUT GET failure\n' >&2
        exit 1
    fi
    cat "$FAKE_LIVE_RULESET"
    exit 0
fi

if [[ "$method" != "PUT" || -z "$input" ]]; then
    printf 'expected PUT with --input, got method=%s input=%s\n' "$method" "$input" >&2
    exit 64
fi

put_count=$((put_count + 1))
printf '%s\n' "$put_count" > "$FAKE_PUT_COUNT_FILE"
cp "$input" "$FAKE_LOG_DIR/put-${put_count}.json"
cp "$input" "$FAKE_LIVE_RULESET"

if [[ "${FAKE_FAIL_FIRST_PUT_AFTER_APPLY:-0}" == "1" && "$put_count" == "1" ]]; then
    printf 'simulated lost response after applied PUT\n' >&2
    exit 1
fi

if [[ "${FAKE_TAMPER_FIRST_PUT:-0}" == "1" && "$put_count" == "1" ]]; then
    jq '(.rules[] | select(.type == "required_status_checks")
        | .parameters.required_status_checks) |= map(select(.context != "lint"))' \
        "$FAKE_LIVE_RULESET" > "$FAKE_LOG_DIR/tampered.json"
    cp "$FAKE_LOG_DIR/tampered.json" "$FAKE_LIVE_RULESET"
fi

cat "$FAKE_LIVE_RULESET"
