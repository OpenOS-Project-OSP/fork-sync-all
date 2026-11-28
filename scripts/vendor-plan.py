#!/usr/bin/env python3
"""Validate and render a deterministic, non-mutating FSA vendor operation plan.

This first-stage planner performs no network access, credential lookup, or writes.
It intentionally accepts dry_run=true only; execution belongs to a later,
approval-gated implementation.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
SCHEMA_PATH = REPO_ROOT / "schema" / "vendor-operation.schema.json"
DIRECTIONS = {"to_vendor", "from_vendor", "serve_as_vendor"}
ACTIONS = {"discover", "plan_export", "plan_import", "plan_serve"}
ACTION_FOR_DIRECTION = {
    "to_vendor": {"discover", "plan_export"},
    "from_vendor": {"discover", "plan_import"},
    "serve_as_vendor": {"discover", "plan_serve"},
}
SECRET_KEYS = {"token", "password", "secret", "private_key", "access_token", "api_key"}


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def validate_operation(data: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(data, dict):
        return ["operation root must be a JSON object"]

    try:
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"cannot load operation schema: {exc}"]

    for field in schema["required"]:
        if field not in data:
            errors.append(f"missing required field '{field}'")
    if data.get("schema_version") != "1.0":
        errors.append("schema_version must be '1.0'")
    if not _nonempty(data.get("operation_id")) or len(data.get("operation_id", "")) > 128:
        errors.append("operation_id must be a non-empty string of at most 128 characters")
    if not _nonempty(data.get("idempotency_key")) or len(data.get("idempotency_key", "")) < 16:
        errors.append("idempotency_key must contain at least 16 characters")
    if not _nonempty(data.get("correlation_id")):
        errors.append("correlation_id must be a non-empty string")
    direction = data.get("direction")
    if direction not in DIRECTIONS:
        errors.append(f"direction must be one of: {', '.join(sorted(DIRECTIONS))}")
    action = data.get("requested_action")
    if action not in ACTIONS:
        errors.append(f"requested_action must be one of: {', '.join(sorted(ACTIONS))}")
    elif direction in ACTION_FOR_DIRECTION and action not in ACTION_FOR_DIRECTION[direction]:
        errors.append(f"requested_action '{action}' is not valid for direction '{direction}'")
    if data.get("dry_run") is not True:
        errors.append("only dry_run=true is accepted by this non-mutating planner")

    provider = data.get("provider")
    if not isinstance(provider, dict):
        errors.append("provider must be an object")
    else:
        for field in ("provider_id", "provider_type"):
            if not _nonempty(provider.get(field)):
                errors.append(f"provider.{field} must be a non-empty string")
        capabilities = provider.get("capabilities")
        if not isinstance(capabilities, list) or not all(_nonempty(x) for x in capabilities):
            errors.append("provider.capabilities must be an array of non-empty strings")
        if "credential_ref" in provider and not _nonempty(provider["credential_ref"]):
            errors.append("provider.credential_ref must be a non-empty protected-secret reference")

    for endpoint_name in ("source", "destination"):
        endpoint = data.get(endpoint_name)
        if not isinstance(endpoint, dict):
            errors.append(f"{endpoint_name} must be an object")
            continue
        for field in ("platform", "host", "owner", "repository", "object"):
            if not _nonempty(endpoint.get(field)):
                errors.append(f"{endpoint_name}.{field} must be a non-empty string")

    authority = data.get("authority")
    if not isinstance(authority, dict) or authority.get("system") not in {
        "fsa_canonical", "external_provider", "consumer_contract"
    }:
        errors.append("authority.system must explicitly identify the authoritative system")
    elif not isinstance(authority.get("object_scope"), list) or not authority["object_scope"]:
        errors.append("authority.object_scope must be a non-empty array")

    policy = data.get("ownership_policy")
    if not isinstance(policy, dict):
        errors.append("ownership_policy must be an object")
    else:
        if policy.get("source_of_truth") not in {"source", "destination", "explicit_authority"}:
            errors.append("ownership_policy.source_of_truth must be explicit")
        if not isinstance(policy.get("allow_mutation"), bool):
            errors.append("ownership_policy.allow_mutation must be boolean")
        if not isinstance(policy.get("approval_required"), bool):
            errors.append("ownership_policy.approval_required must be boolean")
        if policy.get("allow_mutation") is True and policy.get("approval_required") is not True:
            errors.append("mutations must require approval")
        if policy.get("conflict_strategy") not in {
            "reject", "manual_review", "source_wins", "destination_wins"
        }:
            errors.append("ownership_policy.conflict_strategy is invalid")

    def scan_secrets(value: Any, path: str = "$") -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                if key.lower() in SECRET_KEYS:
                    errors.append(f"{path}.{key}: raw credentials are forbidden; use provider.credential_ref")
                scan_secrets(child, f"{path}.{key}")
        elif isinstance(value, list):
            for index, child in enumerate(value):
                scan_secrets(child, f"{path}[{index}]")

    scan_secrets(data)
    return errors


def build_plan(operation: dict[str, Any]) -> dict[str, Any]:
    mutations = operation.get("planned_mutations", [])
    return {
        "schema_version": "1.0",
        "operation_id": operation["operation_id"],
        "idempotency_key": operation["idempotency_key"],
        "correlation_id": operation["correlation_id"],
        "direction": operation["direction"],
        "requested_action": operation["requested_action"],
        "provider_id": operation["provider"]["provider_id"],
        "source": operation["source"],
        "destination": operation["destination"],
        "authority": operation["authority"],
        "dry_run": True,
        "execution_enabled": False,
        "status": "planned",
        "planned_mutation_count": len(mutations),
        "planned_mutations": mutations,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", help="Path to a vendor operation JSON document")
    parser.add_argument("--output", help="Optional path for the generated plan JSON")
    args = parser.parse_args()
    try:
        operation = json.loads(Path(args.operation).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"vendor-plan: cannot read operation: {exc}", file=sys.stderr)
        return 2
    errors = validate_operation(operation)
    if errors:
        print(f"vendor-plan: rejected ({len(errors)} validation error(s))", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    plan = build_plan(operation)
    rendered = json.dumps(plan, indent=2, sort_keys=True) + "\n"
    if args.output:
        Path(args.output).write_text(rendered, encoding="utf-8")
    else:
        sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
