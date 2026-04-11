#!/usr/bin/env bash
# scripts/lib/sanitize.sh — JSON sanitization and input validation
#
# Defense-in-depth sanitization for YAML-derived values before they are
# embedded in JSON payloads or shell commands.
#
# All JSON construction in this codebase already uses `jq --arg` for safe
# escaping. This library provides:
#   1. A `json_escape` function for ad-hoc string escaping (e.g. in export.sh)
#   2. Input validation that rejects null bytes and C0 control characters
#      (other than common whitespace) that have no place in agent field values.
#
# Usage:
#   source scripts/lib/sanitize.sh
#   validated="$(validate_field "taskDescription" "$raw_value")" || exit 1
#   escaped="$(json_escape "$value")"

set -euo pipefail

# json_escape — Safely JSON-encode a string value (the bare scalar, no outer
# object/array).  The result is a JSON string literal including the surrounding
# double quotes, suitable for direct embedding in a JSON document when you
# cannot use `jq --arg`.
#
# Usage:
#   json_escape "He said \"hello\""
#   # outputs: "He said \"hello\""
#
# Implementation: delegates entirely to jq so the escaping rules are identical
# to what `jq --arg` produces.
json_escape() {
    local value="$1"
    printf '%s' "$value" | jq -Rsa '.'
}

# validate_field — Reject values containing null bytes or raw C0 control
# characters (bytes 0x00-0x08, 0x0B-0x0C, 0x0E-0x1F, 0x7F) that should never
# appear in YAML agent field values.  Tab (0x09), newline (0x0A), and carriage
# return (0x0D) are permitted because they can legitimately appear in multi-line
# taskDescription values.
#
# Usage:
#   validate_field "fieldName" "$value" || exit 1
#
# On success: prints $value unchanged.
# On failure: prints an error to stderr and returns 1.
validate_field() {
    local field="$1"
    local value="$2"

    # Detect null bytes (0x00) — these can never be in valid shell strings but
    # guard explicitly in case a future code path processes binary data.
    if printf '%s' "$value" | grep -qP '\x00'; then
        echo "ERROR: field '${field}' contains a null byte (0x00) — rejecting." >&2
        return 1
    fi

    # Detect non-whitespace C0 control characters: 0x01-0x08, 0x0B-0x0C, 0x0E-0x1F, 0x7F
    # (0x09=TAB, 0x0A=LF, 0x0D=CR are allowed)
    if printf '%s' "$value" | grep -qP '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]'; then
        echo "ERROR: field '${field}' contains disallowed control characters — rejecting." >&2
        return 1
    fi

    printf '%s' "$value"
}

# validate_agent_fields — Validate all agent fields extracted from a YAML file.
# Calls validate_field for each parameter. Returns 1 on first failure.
#
# Usage:
#   validate_agent_fields "$name" "$label" "$program" "$workdir" \
#                         "$args" "$desc" "$tags" "$owner" "$role"
validate_agent_fields() {
    local name="$1" label="$2" program="$3" workdir="$4"
    local args="$5" desc="$6" tags="$7" owner="$8" role="$9"

    validate_field "name"             "$name"    > /dev/null || return 1
    validate_field "label"            "$label"   > /dev/null || return 1
    validate_field "program"          "$program" > /dev/null || return 1
    validate_field "workingDirectory" "$workdir" > /dev/null || return 1
    validate_field "programArgs"      "$args"    > /dev/null || return 1
    validate_field "taskDescription"  "$desc"    > /dev/null || return 1
    validate_field "tags"             "$tags"    > /dev/null || return 1
    validate_field "owner"            "$owner"   > /dev/null || return 1
    validate_field "role"             "$role"    > /dev/null || return 1
}
