#!/usr/bin/env python3
"""Validate desired Agents, Fleets, and ExecutionPools without runtime access.

The historical filename remains a supported CI entry point. JSON schemas check
document shape; this validator checks references and resource arithmetic.
"""

import argparse
from collections import Counter
import json
from pathlib import Path
import sys
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import jsonschema
import yaml

SCHEMAS = {
    "Agent": "agent-v1.schema.json",
    "Fleet": "fleet-v1.schema.json",
    "ExecutionPool": "execution-pool-v1.schema.json",
}
SCHEMA_ROOT = Path(__file__).resolve().parents[1] / "schemas"
DIRECTORIES = {"Agent": "agents", "Fleet": "fleets", "ExecutionPool": "pools"}


def load_documents(root, errors):
    validators = {}
    for kind, filename in SCHEMAS.items():
        schema = json.loads((SCHEMA_ROOT / filename).read_text())
        jsonschema.Draft202012Validator.check_schema(schema)
        validators[kind] = jsonschema.Draft202012Validator(schema)
    documents = []
    for directory in ("agents", "fleets", "pools"):
        for path in sorted((root / directory).rglob("*.yaml")):
            try:
                document = yaml.safe_load(path.read_text())
            except (OSError, yaml.YAMLError) as error:
                errors.append(f"{path}: YAML parse error: {error}")
                continue
            if not isinstance(document, dict):
                errors.append(f"{path}: expected a document object")
                continue
            kind = document.get("kind")
            if not isinstance(kind, str) or kind not in validators:
                errors.append(f"{path}: unknown document kind {kind!r}")
                continue
            if directory != DIRECTORIES[kind]:
                errors.append(f"{path}: {kind} belongs in {DIRECTORIES[kind]}/")
                continue
            violations = list(validators[kind].iter_errors(document))
            for violation in violations:
                location = ".".join(map(str, violation.absolute_path))
                errors.append(f"{path}: schema {location}: {violation.message}")
            if not violations:
                documents.append((path, document))
    if not documents and not errors:
        errors.append(f"{root}: empty dataset")
    return documents


def check_pool(path, document, errors, identities):
    spec = document["spec"]
    for resource in ("cpus", "memoryGiB"):
        if spec["overhead"][resource] + spec["workload"][resource] > spec["allocation"][resource]:
            errors.append(f"{path}: {resource} overhead + workload exceeds allocation per worker")
    if len(spec["workerProfiles"]) != spec["workers"]:
        errors.append(f"{path}: workerProfiles count must equal workers")
    for profile in spec["workerProfiles"]:
        for field in ("workerId", "privateHomeRef", "authProfileRef"):
            if field not in profile:
                continue
            identity = (field, profile[field])
            if identity in identities:
                errors.append(f"{path}: duplicate {field} {profile[field]!r}; already used in {identities[identity]}")
            identities[identity] = path
    schedule = spec["schedule"]
    if not schedule["submit"] < schedule["drain"] < schedule["terminate"]:
        errors.append(f"{path}: schedule requires submit < drain < terminate on the same local day")
    try:
        ZoneInfo(schedule["timezone"])
    except (ZoneInfoNotFoundError, ValueError):
        errors.append(f"{path}: schedule has unknown IANA timezone {schedule['timezone']!r}")
    if schedule["enabled"] and not spec["admission"]["enabled"]:
        errors.append(f"{path}: schedule cannot be enabled while admission is disabled")
    if spec["admission"]["enabled"] and spec["backend"] != "native" and not spec["container"]["image"]:
        errors.append(f"{path}: unresolved image blocks enabled admission")


def check_agent_pool(spec, default, pools, path, errors, selected=None, host=None):
    reference = spec.get("poolRef", default)
    if reference is None:
        return
    if reference not in pools:
        errors.append(f"{path}: unknown pool {reference!r}")
        return
    pool_spec = pools[reference][1]["spec"]
    if pool_spec["purpose"] != "agents":
        errors.append(f"{path}: agent poolRef {reference!r} selects build-only capacity")
    elif spec["program"] != pool_spec["runtime"]["program"]:
        errors.append(f"{path}: program does not match poolRef {reference!r}")
    if selected is not None and reference not in selected:
        errors.append(f"{path}: poolRef {reference!r} is outside this Fleet's executionPools")
    if host is not None and host != pool_spec["host"]:
        errors.append(f"{path}: agent host {host!r} differs from pool host {pool_spec['host']!r}")


def validate(root, target=None, runnable=False):
    errors = []
    documents = load_documents(root, errors)
    pools, fleets, agents = {}, {}, {}
    identities = {}
    for path, document in documents:
        kind, name = document["kind"], document["metadata"]["name"]
        if kind in ("ExecutionPool", "Fleet"):
            index = pools if kind == "ExecutionPool" else fleets
            if name in index:
                errors.append(f"{path}: duplicate {kind} name {name!r}")
            index[name] = (path, document)
        else:
            relative = path.relative_to(root / "agents").with_suffix("")
            agents[relative.as_posix()] = (path, document)
        if kind == "ExecutionPool":
            check_pool(path, document, errors, identities)

    for path, document in agents.values():
        check_agent_pool(document["spec"], None, pools, path, errors,
                         host=document["metadata"]["host"])

    capacities = {}
    for name, (path, document) in fleets.items():
        spec = document["spec"]
        selected = spec.get("executionPools")
        by_host, groups = Counter(), {}
        for reference in selected or []:
            if reference not in pools:
                errors.append(f"{path}: unknown pool {reference!r}")
                continue
            pool_spec = pools[reference][1]["spec"]
            group = pool_spec.get("exclusiveGroup")
            if group and group in groups:
                errors.append(f"{path}: exclusive group {group!r} selects both {groups[group]} and {reference}")
            if group:
                groups[group] = reference
            if pool_spec["purpose"] == "agents":
                by_host[pool_spec["host"]] += pool_spec["workers"] * pool_spec["conversationsPerWorker"]
        capacity = sum(by_host.values())
        capacities[name] = {"capacity": capacity, "byHost": dict(by_host)}
        if "expectedCapacity" in spec and capacity != spec["expectedCapacity"]:
            errors.append(f"{path}: capacity {capacity} differs from expectedCapacity {spec['expectedCapacity']}")
        if "expectedCapacityByHost" in spec and dict(by_host) != spec["expectedCapacityByHost"]:
            errors.append(f"{path}: capacity by host {dict(by_host)} differs from expectedCapacityByHost")
        if "poolRef" in spec and spec["poolRef"] not in pools:
            errors.append(f"{path}: unknown pool {spec['poolRef']!r}")
        for member in spec.get("agents", []):
            host = document["metadata"].get("host")
            if "ref" in member:
                if member["ref"] not in agents:
                    errors.append(f"{path}: unknown agent ref {member['ref']!r}")
                    continue
                agent = agents[member["ref"]][1]
                member, host = agent["spec"], agent["metadata"]["host"]
            check_agent_pool(member, spec.get("poolRef"), pools, path, errors, selected, host)

    if target and target not in fleets:
        errors.append(f"unknown fleet {target!r}")
    if runnable:
        if not target:
            errors.append("--runnable requires --fleet to select one execution target")
        elif target in fleets:
            selected = fleets[target][1]["spec"].get("executionPools", [])
            if not selected:
                errors.append(f"{target}: runnable Fleet requires executionPools")
            for reference in selected:
                if reference not in pools:
                    continue
                spec = pools[reference][1]["spec"]
                if not spec["admission"]["enabled"]:
                    errors.append(f"{reference}: admission is disabled")
                if spec["backend"] != "native" and not spec["container"]["image"]:
                    errors.append(f"{reference}: unresolved image blocks runnable validation")
    return errors, len(documents), capacities


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="Dataset root")
    parser.add_argument("--fleet", help="Fleet metadata.name to report or check as runnable")
    parser.add_argument("--runnable", action="store_true", help="Require selected pool admission and resolved image pins; performs no runtime checks")
    args = parser.parse_args()
    errors, count, capacities = validate(args.root.resolve(), args.fleet, args.runnable)
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    if errors:
        return 1
    print(f"Validated {count} definitions; all offline checks passed.")
    if args.fleet:
        print(json.dumps({"fleet": args.fleet, **capacities[args.fleet]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
