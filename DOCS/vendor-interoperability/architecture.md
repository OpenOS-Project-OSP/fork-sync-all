# FSA Vendor Interoperability Architecture

**Status:** architecture baseline and audit; implementation is not yet enabled by this document.

## Purpose

FSA needs three distinct capabilities over one shared provider-neutral interoperability core:

| Engine | Direction | Responsibility |
|---|---|---|
| **FSA to Vendor** | FSA → external provider | Publish or export selected repositories, refs, metadata, releases, packages, and artifacts to a configured vendor/platform. |
| **Vendor to FSA** | external provider → FSA | Discover, import, and ingest approved repositories, refs, metadata, releases, packages, and upstream changes into FSA-managed systems. |
| **FSA as Vendor** | consumer ↔ FSA provider contract | Let downstream systems discover and consume FSA-managed repositories, artifacts, metadata, and services through stable, documented provider interfaces. |

These engines are not aliases for mirroring. Repository mirroring, upstream ingestion, artifact/package publication, OTA/template delivery, and an FSA-hosted provider/API are separate operation classes.

## Existing capability map (initial audit)

| Existing component | Current role | Relationship to the proposed subsystem |
|---|---|---|
| `scripts/import-repo.sh` + `import-repo.yml` | Imports Git-compatible source repositories into the canonical FSA owner; can optionally register ongoing sync and mirror onward. | Vendor to FSA foundation; needs explicit trust, ownership, and import-policy metadata. |
| `registered-imports.json` + `scripts/sync-registered-imports.sh` | Tracks imported sources and re-syncs all branches/tags to the FSA counterpart. | Vendor to FSA adapter/transport; current schema is minimal and needs provenance, policy, checkpoint, and conflict fields. |
| `scripts/mirror-orgs.sh` + mirror workflows | Pushes configured FSA repositories outward through OSP/OOC and GitLab mirror chain. | FSA to Vendor; currently specialized around the mirror chain and must retain canonical-source authority. |
| `git-platform-sync.yml` | Configurable push/pull/both synchronization for GitHub, GitLab, Gitea, Forgejo, and Codeberg. | Closest existing provider-neutral git adapter; bidirectional mode needs explicit per-direction authority and conflict policies. |
| `scripts/sync-registry-sources.sh` | Syncs declared upstream dependencies and feature branches using a registry. | Vendor to FSA/upstream sync pattern; useful registry precedent, not a universal vendor contract. |
| `sync-uaa-vendor.yml` | Vendors the UAA source tree into FSA-owned paths. | A concrete Vendor to FSA source-vendoring workflow; should remain distinct from runtime API exposure. |
| `mirror-releases.sh`, `mirror-artifacts.sh`, GHCR/PyPI/RPM/Flatpak workflows | Replicates or publishes release and package artifacts. | FSA to Vendor artifact adapters; must carry signatures, checksums, licenses, SBOMs, and provenance where available. |
| OTA workflows and `config/ota-registry.yml` | Opt-in template/OTA updates to downstream forks. | A form of FSA-as-provider distribution, but not a general discovery or artifact API. |
| `fsa-api/core/adapters/bdfs/import.sh` | Imports a BDFS workspace/image into a local execution environment, with a dry-run option. | Local execution adapter; not itself a remote vendor integration. |
| `fsa-api` / UAA | Provides API and adapter infrastructure. | Potential FSA-as-Vendor control surface, but route-level authentication/authorization must be verified before network exposure. |
| `check-vendor-agnostic.sh` / vendor tree | Detects deployment-specific fallback values in vendored components. | Useful vendor hygiene guard; not a provider registry or sync policy engine. |

This map is a source-level inventory, not a claim that every workflow has been end-to-end validated.

## Shared core contract

The three engines should use a versioned, provider-neutral operation envelope. A future schema should include at least:

- `schema_version`, `operation_id`, `idempotency_key`, `correlation_id`
- `direction`: `to_vendor`, `from_vendor`, or `serve_as_vendor`
- `provider_id`, `provider_type`, `provider_capabilities`
- `source` and `destination` canonical identities, including platform, host, owner/group, repository, ref, and object identity
- `authority` and `ownership_policy` for each repository/ref/path/artifact/metadata class
- `trust_level`, `provenance`, source commit/object digest, and parent/ancestry information
- `requested_action`, `planned_mutations`, `approval_requirement`, and `dry_run`
- `checkpoint`, retry budget, timeout/resource bounds, and conflict strategy
- `result`, structured status, timestamps, and redacted audit metadata

The exact JSON/YAML schema should be introduced separately with schema validation and fixtures; this document does not pretend that such a schema already exists.

## Required invariants

1. **Canonical authority is explicit.** External vendor presence never makes that vendor authoritative for an FSA canonical repository.
2. **No implicit write-back.** Vendor-to-FSA mutations require a registered source, explicit scope, policy approval, and appropriate protected credentials.
3. **Loop prevention.** Use stable origin IDs, operation IDs, idempotency keys, content digests, and ancestry to prevent echo loops across mirror chains.
4. **Dry-run first.** New providers begin with read-only discovery and deterministic dry-run plans.
5. **Least privilege.** Credentials are referenced from protected provider configuration; never committed, printed, or copied into operation records.
6. **Provenance and integrity.** Preserve or verify signatures, checksums, licenses, SBOMs, attestations, and source identity; quarantine unverifiable artifacts when policy requires.
7. **Bounded execution.** Enforce endpoint allowlists, payload and resource limits, timeouts, rate limits, and redirect/SSRF protections.
8. **Auditable state.** Record actor, provider, direction, objects, policy decision, plan, checkpoint, and result without secrets.
9. **No unauthenticated service exposure.** FSA-as-Vendor network interfaces stay disabled or loopback-contained until route-level authentication and authorization are verified.
10. **No behavior change by stealth.** Existing mirror/import workflows remain unchanged until each migration has parity tests and a rollback plan.

## Proposed subsystem boundaries

- **Vendor Registry Engine:** provider identities, capabilities, endpoints, trust roots, credential references, and opt-in status.
- **Vendor Policy Engine:** source-of-truth, ownership, allowed directions, object scopes, approvals, and conflict rules.
- **Vendor Plan Engine:** read-only discovery, diff/preview, deterministic mutation plan, and dry-run reporting.
- **Vendor Transfer Engine:** shared bounded transport, retries, checkpoints, rate-limit handling, and integrity verification.
- **Vendor Provenance Engine:** origin graph, content digests, attestations, licenses, SBOMs, and audit records.
- **FSA to Vendor Engine:** outbound repository/ref/release/package/artifact publication adapters.
- **Vendor to FSA Engine:** inbound discovery/import/upstream synchronization adapters.
- **FSA as Vendor Engine:** authenticated catalog, metadata, repository/artifact delivery, and consumer-facing contracts.
- **Status Checks Engine / Check Status Engine:** report policy, plan, transfer, verification, and reconciliation outcomes as machine-readable checks; do not confuse creating a check with polling/evaluating its state.

The shared core should be implemented once. The three directional engines should orchestrate it rather than independently reimplement authentication, retries, provenance, and conflict detection.

## Phased delivery

1. **Audit and contracts:** complete the workflow/registry inventory, define ownership vocabulary, threat model, and schema.
2. **Read-only foundation:** provider registry, capability discovery, provenance records, deterministic dry-run plans, and fixture tests.
3. **Reference adapters:** first use existing GitHub/GitLab paths for one safe outbound and one safe inbound read-only/dry-run case.
4. **Controlled mutations:** add approval-gated import/export with idempotency, checkpoints, conflict handling, compensation/rollback, and status checks.
5. **FSA as Vendor:** expose a versioned catalog and artifact/repository contract behind verified authentication and authorization; add consumer conformance tests.
6. **Migration:** migrate existing workflows one at a time after parity and end-to-end tests; preserve current mirror-chain authority and provide rollback.

## Initial end-to-end test matrix

- provider discovery succeeds with read-only credentials and degrades safely without credentials;
- dry-run output matches the subsequent approved operation;
- repeat operation is idempotent and does not create duplicate commits/releases/artifacts;
- echoing an exported object back through another provider is detected as a loop;
- conflicting updates are reported and never silently resolved by timestamp alone;
- partial transfer resumes from a validated checkpoint;
- stale or tampered digests, signatures, or provenance are rejected/quarantined;
- unauthorized provider, endpoint, repository, ref, or artifact scope is denied;
- secrets never appear in logs, artifacts, reports, or committed state;
- FSA-as-Vendor consumers cannot access unapproved/private objects and cannot invoke write operations without explicit authorization.

## Out of scope for this baseline

- Enabling new write-capable vendor workflows.
- Changing canonical mirror-chain direction or source of truth.
- Opening FSA API network access.
- Treating package registries, Git forges, and local BDFS import backends as interchangeable provider types.
- Declaring any adapter production-ready before its own end-to-end evidence exists.

## Related work

- FSA issue #1205: Vendor Interoperability design and implementation tracking.
- FSA PR #1203: API loopback containment (pending validation repair).
- FSA PR #1204: UAA full vendor checkout fix (merged).
