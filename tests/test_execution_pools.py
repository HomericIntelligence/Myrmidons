"""Offline tests for desired Fleet state; no runtime or account access."""

import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

import jsonschema
import yaml


ROOT = Path(__file__).resolve().parents[1]


def pool(name="laptop-native", host="laptop"):
    return {
        "apiVersion": "myrmidons/v1", "kind": "ExecutionPool",
        "metadata": {"name": name, "displayName": name},
        "spec": {
            "host": host, "backend": "native", "purpose": "agents",
            "workers": 1, "conversationsPerWorker": 12,
            "allocation": {"cpus": 8, "memoryGiB": 12, "gpus": 0},
            "overhead": {"cpus": 2, "memoryGiB": 4},
            "workload": {"cpus": 6, "memoryGiB": 8},
            "workerProfiles": [{
                "workerId": name + "-01", "privateHomeRef": name + "-home-01",
                "permissionProfileRef": "isolated-contributor",
                "authProfileRef": name + "-auth-01",
            }],
            "runtime": {
                "program": "codex", "version": "0.153.4", "nestedAgents": False,
                "authentication": "independent-native-login",
            },
            "admission": {"enabled": False},
            "schedule": {
                "enabled": False, "timezone": "America/Los_Angeles",
                "weekdays": [1, 2, 3, 4, 5], "submit": "08:00",
                "drain": "17:00", "terminate": "18:00",
            },
        },
    }


def fleet(refs=None):
    return {
        "apiVersion": "myrmidons/v1", "kind": "Fleet",
        "metadata": {"name": "target"},
        "spec": {"executionPools": refs or ["laptop-native"], "expectedCapacity": 12},
    }


class ExecutionPoolTests(unittest.TestCase):
    def check_dataset(self, documents, *args):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for relative, document in documents.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(yaml.safe_dump(document))
            return subprocess.run(
                [sys.executable, str(ROOT / "scripts/validate-agent-schemas.py"),
                 "--root", str(root), *args],
                capture_output=True, text=True, cwd=ROOT, check=False,
            )

    def assert_rejected(self, documents, text, *args):
        result = self.check_dataset(documents, *args)
        self.assertNotEqual(0, result.returncode, result.stdout)
        self.assertIn(text, result.stderr)

    def test_codex_schema_supports_pool_and_hmas_identity(self):
        agent = {
            "apiVersion": "myrmidons/v1",
            "kind": "Agent",
            "metadata": {"name": "pipeline-task", "host": "laptop"},
            "spec": {
                "program": "codex",
                "workingDirectory": "/work/pipeline-task",
                "poolRef": "laptop-native",
                "role": "member",
                "executionDomain": "pipeline",
                "hmasRole": "task-agent",
            },
        }
        schema = json.loads((ROOT / "schemas/agent-v1.schema.json").read_text())
        errors = list(jsonschema.Draft202012Validator(schema).iter_errors(agent))
        self.assertEqual([], [error.message for error in errors])

    def test_resource_budget_is_per_worker_and_cannot_overcommit(self):
        for resource in ("cpus", "memoryGiB"):
            with self.subTest(resource=resource):
                document = pool()
                document["spec"]["workload"][resource] += 1
                self.assert_rejected({"pools/laptop-native.yaml": document}, resource)

    def test_pool_references_must_resolve(self):
        self.assert_rejected({"fleets/target.yaml": fleet()}, "unknown pool")

    def test_pool_default_applies_to_inline_agents(self):
        document = fleet()
        document["spec"]["poolRef"] = "missing"
        document["spec"]["agents"] = [{
            "name": "work", "program": "codex", "workingDirectory": "/work",
            "role": "member", "executionDomain": "pipeline", "hmasRole": "task-agent",
        }]
        self.assert_rejected({"pools/laptop-native.yaml": pool(), "fleets/target.yaml": document},
                             "unknown pool")

    def test_administrative_role_cannot_be_a_task_role(self):
        document = fleet()
        document["spec"]["agents"] = [{
            "name": "work", "program": "codex", "workingDirectory": "/work",
            "role": "task-agent",
        }]
        self.assert_rejected({"pools/laptop-native.yaml": pool(), "fleets/target.yaml": document},
                             "schema")

    def test_capacity_mismatch_and_missing_per_host_capacity_fail(self):
        document = fleet()
        document["spec"]["expectedCapacity"] = 108
        self.assert_rejected({"pools/laptop-native.yaml": pool(), "fleets/target.yaml": document},
                             "capacity")
        document["spec"]["expectedCapacity"] = 12
        document["spec"]["expectedCapacityByHost"] = {"laptop": 12, "m1": 48, "m2": 48}
        self.assert_rejected({"pools/laptop-native.yaml": pool(), "fleets/target.yaml": document},
                             "capacity")

    def test_laptop_comparison_profiles_are_mutually_exclusive(self):
        first, second = pool(), pool("laptop-container")
        first["spec"]["exclusiveGroup"] = "laptop-comparison"
        second["spec"]["exclusiveGroup"] = "laptop-comparison"
        document = fleet(["laptop-native", "laptop-container"])
        document["spec"]["expectedCapacity"] = 24
        self.assert_rejected({"pools/a.yaml": first, "pools/b.yaml": second,
                              "fleets/target.yaml": document}, "exclusive")

    def test_private_auth_homes_and_worker_ids_cannot_be_shared(self):
        for field in ("workerId", "privateHomeRef", "authProfileRef"):
            with self.subTest(field=field):
                first, second = pool(), pool("other")
                second["spec"]["workerProfiles"][0][field] = first["spec"]["workerProfiles"][0][field]
                self.assert_rejected({"pools/a.yaml": first, "pools/b.yaml": second}, field)

    def test_nested_agents_and_wrong_worker_profile_counts_are_rejected(self):
        document = pool()
        document["spec"]["runtime"]["nestedAgents"] = True
        self.assert_rejected({"pools/a.yaml": document}, "schema")
        document = pool()
        document["spec"]["workers"] = 2
        self.assert_rejected({"pools/a.yaml": document}, "workerProfiles")

    def test_unresolved_image_never_passes_runnable_validation(self):
        document = pool()
        document["spec"]["backend"] = "container"
        document["spec"]["container"] = {"image": None}
        result = self.check_dataset({"pools/a.yaml": document, "fleets/target.yaml": fleet()})
        self.assertEqual(0, result.returncode, result.stderr)
        self.assert_rejected({"pools/a.yaml": document, "fleets/target.yaml": fleet()},
                             "unresolved image", "--runnable", "--fleet", "target")
        document["spec"]["admission"]["enabled"] = True
        self.assert_rejected({"pools/a.yaml": document}, "unresolved image")

    def test_tagged_image_is_not_a_pin(self):
        document = pool()
        document["spec"]["backend"] = "container"
        document["spec"]["container"] = {"image": "ghcr.io/example/fleet:latest"}
        self.assert_rejected({"pools/a.yaml": document}, "schema")

    def test_disabled_pool_cannot_be_reported_runnable(self):
        self.assert_rejected({"pools/a.yaml": pool(), "fleets/target.yaml": fleet()},
                             "admission is disabled", "--runnable", "--fleet", "target")

    def test_build_pools_have_no_provider_auth_and_no_agent_capacity(self):
        build = pool("builds", "m1")
        build["spec"]["purpose"] = "builds"
        build["spec"]["conversationsPerWorker"] = 0
        del build["spec"]["runtime"]
        self.assert_rejected({"pools/builds.yaml": build}, "authProfileRef")
        del build["spec"]["workerProfiles"][0]["authProfileRef"]
        target = fleet(["laptop-native", "builds"])
        result = self.check_dataset({"pools/a.yaml": pool(), "pools/builds.yaml": build,
                                     "fleets/target.yaml": target})
        self.assertEqual(0, result.returncode, result.stderr)

    def test_schedule_requires_submission_before_drain_and_deadline(self):
        document = pool()
        document["spec"]["schedule"]["drain"] = "07:59"
        self.assert_rejected({"pools/a.yaml": document}, "schedule")

    def test_extensible_domain_and_role_remain_valid(self):
        target = fleet()
        target["spec"]["agents"] = [{
            "name": "work", "program": "codex", "workingDirectory": "/work",
            "poolRef": "laptop-native", "role": "member",
            "executionDomain": "future-domain", "hmasRole": "deep-specialist",
        }]
        result = self.check_dataset({"pools/a.yaml": pool(), "fleets/target.yaml": target})
        self.assertEqual(0, result.returncode, result.stderr)

    def test_existing_dataset_and_both_108_targets_validate(self):
        for target in (None, "homeric-fleet-native", "homeric-fleet-container"):
            with self.subTest(target=target):
                args = [sys.executable, str(ROOT / "scripts/validate-agent-schemas.py")]
                if target:
                    args.extend(["--fleet", target])
                result = subprocess.run(args, capture_output=True, text=True, cwd=ROOT, check=False)
                self.assertEqual(0, result.returncode, result.stderr)
                if target:
                    self.assertIn("108", result.stdout)

    def test_malformed_yaml_is_a_diagnostic_not_a_traceback(self):
        self.assert_rejected({"pools/a.yaml": None}, "object")

    def test_missing_target_is_not_success(self):
        self.assert_rejected({"pools/a.yaml": pool()}, "unknown fleet", "--fleet", "missing")

    def test_empty_dataset_is_not_success(self):
        self.assert_rejected({}, "empty dataset")

    def test_document_kind_must_match_its_directory(self):
        document = {
            "apiVersion": "myrmidons/v1", "kind": "Agent",
            "metadata": {"name": "misplaced", "host": "laptop"},
            "spec": {"program": "codex", "workingDirectory": "/work"},
        }
        result = self.check_dataset({"pools/misplaced.yaml": document})
        self.assertNotEqual(0, result.returncode)
        self.assertIn("belongs in agents/", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_package_contains_execution_pools(self):
        result = subprocess.run(["just", "package"], capture_output=True, text=True,
                                cwd=ROOT, check=False)
        self.assertEqual(0, result.returncode, result.stderr)
        archives = list((ROOT / "dist").glob("myrmidons-dataset-*.tar.gz"))
        self.assertEqual(1, len(archives))
        with tarfile.open(archives[0]) as archive:
            for path in (ROOT / "pools").glob("*.yaml"):
                self.assertIn("pools/" + path.name, archive.getnames())


if __name__ == "__main__":
    unittest.main()
