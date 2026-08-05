#!/usr/bin/env python3
"""Validate all agent YAML definitions against the agent-v1 schema.

Used by the `build` job in .github/workflows/_required.yml, the merge-queue
smoke workflow, and scripts/run_ci_local.sh. Exits non-zero on any YAML parse
error or schema violation.

Dependencies: pyyaml, jsonschema (uv-managed dev group).
"""

import glob
import json
import sys

import jsonschema
import yaml

SCHEMA_PATH = "schemas/agent-v1.schema.json"


def main() -> int:
    with open(SCHEMA_PATH) as f:
        schema = json.load(f)

    agent_files = glob.glob("agents/**/*.yaml", recursive=True)
    errors = []
    for filepath in sorted(agent_files):
        with open(filepath) as f:
            try:
                doc = yaml.safe_load(f)
            except yaml.YAMLError as e:
                errors.append(f"YAML parse error in {filepath}: {e}")
                continue
        try:
            jsonschema.validate(doc, schema)
        except jsonschema.ValidationError as e:
            errors.append(f"Schema error in {filepath}: {e.message}")

    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1

    print(f"Validated {len(agent_files)} agent definitions — all OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
