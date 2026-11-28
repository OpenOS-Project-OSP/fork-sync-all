"""Tests for the non-mutating vendor operation planner."""
import json
from conftest import run_validator


def valid_operation():
    return {
        "schema_version": "1.0",
        "operation_id": "op-test-0001",
        "idempotency_key": "test-idempotency-key-0001",
        "correlation_id": "trace-test-0001",
        "direction": "to_vendor",
        "provider": {
            "provider_id": "example-forge",
            "provider_type": "git",
            "capabilities": ["discover", "read", "export"],
            "credential_ref": "actions-secret:VENDOR_TOKEN",
        },
        "source": {
            "platform": "github", "host": "github.com", "owner": "org",
            "repository": "source", "ref": "main", "object": "repository",
        },
        "destination": {
            "platform": "gitlab", "host": "gitlab.example.invalid", "owner": "team",
            "repository": "destination", "ref": "main", "object": "repository",
        },
        "authority": {"system": "fsa_canonical", "object_scope": ["repository:source"]},
        "ownership_policy": {
            "source_of_truth": "source", "allow_mutation": False,
            "approval_required": True, "conflict_strategy": "reject",
        },
        "requested_action": "plan_export",
        "dry_run": True,
        "planned_mutations": [{"kind": "create_ref", "ref": "main"}],
    }


def run_plan(tmp_path, operation, *extra):
    path = tmp_path / "operation.json"
    path.write_text(json.dumps(operation))
    return run_validator("vendor-plan.py", str(path), *extra)


def test_valid_operation_emits_non_executable_plan(tmp_path):
    code, output = run_plan(tmp_path, valid_operation())
    assert code == 0
    plan = json.loads(output)
    assert plan["status"] == "planned"
    assert plan["dry_run"] is True
    assert plan["execution_enabled"] is False
    assert plan["planned_mutation_count"] == 1


def test_rejects_non_dry_run_operation(tmp_path):
    operation = valid_operation()
    operation["dry_run"] = False
    code, output = run_plan(tmp_path, operation)
    assert code == 1
    assert "only dry_run=true" in output


def test_rejects_direction_action_mismatch(tmp_path):
    operation = valid_operation()
    operation["direction"] = "from_vendor"
    code, output = run_plan(tmp_path, operation)
    assert code == 1
    assert "not valid for direction" in output


def test_rejects_implicit_authority(tmp_path):
    operation = valid_operation()
    operation["authority"] = {"object_scope": ["repository:source"]}
    code, output = run_plan(tmp_path, operation)
    assert code == 1
    assert "authority.system" in output


def test_rejects_mutation_without_approval(tmp_path):
    operation = valid_operation()
    operation["ownership_policy"]["allow_mutation"] = True
    operation["ownership_policy"]["approval_required"] = False
    code, output = run_plan(tmp_path, operation)
    assert code == 1
    assert "mutations must require approval" in output


def test_rejects_raw_secret_fields(tmp_path):
    operation = valid_operation()
    operation["provider"]["access_token"] = "do-not-store"
    code, output = run_plan(tmp_path, operation)
    assert code == 1
    assert "raw credentials are forbidden" in output


def test_rejects_empty_object_scope(tmp_path):
    operation = valid_operation()
    operation["authority"]["object_scope"] = []
    code, output = run_plan(tmp_path, operation)
    assert code == 1
    assert "object_scope" in output


def test_missing_operation_file_fails_closed(tmp_path):
    code, output = run_validator("vendor-plan.py", str(tmp_path / "missing.json"))
    assert code == 2
    assert "cannot read operation" in output
