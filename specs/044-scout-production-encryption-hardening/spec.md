# Feature Specification: Scout Production Encryption Hardening

**Feature Branch**: `044-scout-production-encryption-hardening`

**Created**: 2026-08-19

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 9/scout/03-production-hardening/spec64.md — guarantee ActiveRecord::Encryption is actually configured and enforced wherever Scout runs in production, and block Scout/ScoutTool records from persisting api_key_override/auth_headers in plaintext when encryption keys are missing."

## Clarifications

### Session 2026-08-19

- Q: Should the encryption keys be delivered to the production Swarm stack specifically via Docker Swarm secrets, or is a plain `environment:` entry in the stack file also an acceptable option for this feature? → A: Allow either Swarm secrets or explicit `environment:` entries, operator's choice

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Operator confirms production encryption is active before enabling Scout (Priority: P1)

An operator deploying the production Docker Swarm stack needs a reliable way to confirm that the three `ActiveRecord::Encryption` keys are generated, present in the running stack, and actually recognized by the application before turning on any Scout assistant that stores an API key or webhook auth header.

**Why this priority**: This is the precondition for the whole feature — without verified encryption in the real production stack, no other Scout capability can safely go live with sensitive credentials.

**Independent Test**: Can be fully tested by generating the encryption keys, deploying them to the production Swarm stack, and confirming the application reports encryption as configured — independent of any Scout record being created.

**Acceptance Scenarios**:

1. **Given** the three encryption keys have been generated and added to the production Swarm stack, **When** the operator checks the running application's encryption status, **Then** it reports encryption as configured.
2. **Given** encryption is configured in production, **When** a `Scout` or `ScoutTool` record is created with `api_key_override` or `auth_headers` populated, **Then** the sensitive value round-trips correctly (is stored encrypted and read back decrypted, matching what was written).
3. **Given** a stack file specifies environment values via `env_file:`, **When** the stack is deployed with `docker stack deploy`, **Then** the operator can verify those values were NOT relied upon for the encryption keys (Swarm secrets or explicit `environment:` entries are used instead).

---

### User Story 2 - System refuses to store secrets in plaintext when encryption is missing (Priority: P1)

If the production environment is misconfigured (encryption keys absent), the system must refuse to create or update a `Scout`/`ScoutTool` record with a populated `api_key_override` or `auth_headers` value, rather than silently saving the credential as plaintext.

**Why this priority**: This is the actual safety guarantee the feature exists to provide — without it, a misconfigured deploy would silently leak commercial API keys and webhook auth headers into the database in plaintext.

**Independent Test**: Can be fully tested in an environment with `RAILS_ENV=production` and no encryption keys configured, by attempting to create a `Scout` with `api_key_override` set (or a `ScoutTool` with `auth_headers` set) and confirming the operation fails loudly instead of persisting.

**Acceptance Scenarios**:

1. **Given** `RAILS_ENV=production` and encryption is not configured, **When** an operator or the application attempts to create a `Scout` record with `api_key_override` set, **Then** the save fails with a clear error and no row is persisted.
2. **Given** `RAILS_ENV=production` and encryption is not configured, **When** an operator attempts to create a `ScoutTool` record with `auth_headers` set, **Then** the save fails with a clear error and no row is persisted.
3. **Given** `RAILS_ENV=production` and encryption is not configured, **When** a `Scout` or `ScoutTool` is created/updated WITHOUT `api_key_override`/`auth_headers` populated (e.g. blank, or an existing record's other attributes are edited), **Then** the save succeeds normally — the block only applies to the specific sensitive fields, not to the models in general.
4. **Given** encryption keys are configured, **When** the same creation attempts from scenarios 1-2 are repeated, **Then** they succeed and the fields are stored encrypted.

---

### User Story 3 - Non-production environments remain unaffected (Priority: P2)

Developers working locally or in staging/test environments without encryption keys configured must continue to be able to create `Scout`/`ScoutTool` records for development purposes, since this hardening is scoped to production safety, not a blanket requirement for every environment.

**Why this priority**: Without this, the hardening would break local development and test suites for Phases 1-2, which already assume Scout records can be created without production-grade key management.

**Independent Test**: Can be fully tested by running the same creation attempts as User Story 2 in a non-production environment (e.g. `RAILS_ENV=development` or `test`) without encryption keys configured, and confirming they succeed as before.

**Acceptance Scenarios**:

1. **Given** `RAILS_ENV=development` (or `test`) and encryption is not configured, **When** a `Scout` is created with `api_key_override` set, **Then** the save succeeds (matching current pre-hardening behavior, consistent with how other core encrypted-if-configured fields behave today).

---

### Edge Cases

- What happens if encryption keys are present but only partially configured (e.g. only 2 of the 3 `ACTIVE_RECORD_ENCRYPTION_*` values are set)? The existing `Chatwoot.encryption_configured?` guard already treats this as "not configured" — the new check reuses that same guard, so partial configuration is treated as unconfigured and blocks the save.
- What happens if an existing `Scout`/`ScoutTool` record (created before encryption was configured, or created in a non-production environment) is later edited in production after keys are added? Its sensitive fields become encrypted correctly on that save, consistent with the round-trip guarantee in User Story 1.
- What happens if an existing plaintext `Scout`/`ScoutTool` record is edited in production while encryption keys are STILL missing, without touching the sensitive fields? Per User Story 2 Scenario 3, this succeeds — the guard is scoped to attempts that populate/change the sensitive fields.
- How does the check behave for the `RAILS_ENV=production` boot process itself (before any Scout record is touched)? Out of scope for a hard boot-time failure per the source spec ("boot-time or deploy-time check" is satisfied by the model-level guard plus an operator-facing verification step; the application does not need to refuse to boot entirely if encryption is unconfigured, since non-Scout production traffic must keep functioning).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The three `ACTIVE_RECORD_ENCRYPTION_*` keys (primary key, deterministic key, key derivation salt) MUST be generated using the project's standard key-generation process and provided to the production Docker Swarm stack via a mechanism that Swarm actually honors at deploy time (Docker Swarm secrets or explicit `environment:` entries — not `env_file:`, which Swarm does not process reliably). The operator chooses between Swarm secrets and explicit `environment:` entries per their own deployment's security posture; this feature does not mandate one over the other.
- **FR-002**: The system MUST provide a way for an operator to confirm, against the actual running production deployment, that encryption is recognized as configured (not just theoretically present in local `.env`).
- **FR-003**: When encryption is confirmed configured in production, creating a `Scout` or `ScoutTool` record with `api_key_override`/`auth_headers` populated MUST result in the value being retrievable afterward exactly as written (round-trip integrity through encryption).
- **FR-004**: The system MUST prevent a `Scout` record from being persisted with a populated `api_key_override` when running with `RAILS_ENV=production` and encryption is not configured, failing the save with a clear, actionable error rather than silently storing plaintext.
- **FR-005**: The system MUST prevent a `ScoutTool` record from being persisted with a populated `auth_headers` when running with `RAILS_ENV=production` and encryption is not configured, failing the save with a clear, actionable error rather than silently storing plaintext.
- **FR-006**: The prevention in FR-004/FR-005 MUST NOT block saves of `Scout`/`ScoutTool` records that do not populate the sensitive fields, and MUST NOT apply outside `RAILS_ENV=production`.
- **FR-007**: The prevention in FR-004/FR-005 MUST reuse the existing `Chatwoot.encryption_configured?` guard as the single source of truth for whether encryption is configured, rather than introducing a second, divergent check.

### Key Entities *(include if feature involves data)*

- **Scout**: Existing entity (introduced in Phase 1) representing an AI assistant configuration; the field of interest here is `api_key_override`, an optional BYOK credential that must never be persisted in plaintext in production.
- **ScoutTool**: Existing entity (introduced in Phase 2) representing an external REST/webhook tool a Scout can call; the field of interest here is `auth_headers`, optional HTTP authentication headers that must never be persisted in plaintext in production.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator can verify, within one deploy cycle, that the production Swarm stack has working encryption for Scout's sensitive fields, with zero manual database inspection required.
- **SC-002**: 100% of attempts to create a `Scout`/`ScoutTool` with a populated sensitive field in a production environment lacking encryption keys are rejected before any data is written.
- **SC-003**: 0% of existing non-production Scout development/test workflows are disrupted by this change (all Phase 1/2 creation flows without encryption configured continue to work outside production).
- **SC-004**: After this feature ships, no `Scout`/`ScoutTool` record containing a populated sensitive field can exist in the production database unless it was written while encryption was confirmed configured.

## Assumptions

- The three `ACTIVE_RECORD_ENCRYPTION_*` keys are generated via the project's existing `bin/rails db:encryption:init` tooling, per the referenced backlog item; this spec does not introduce a new key-generation mechanism.
- "Production" for the purposes of this feature is defined by `RAILS_ENV=production`, consistent with how `Chatwoot.encryption_configured?` and the rest of the codebase already distinguish environments.
- Backfilling any pre-existing plaintext data, key rotation, and external KMS/Vault integration are explicitly out of scope, per the source specification and its parent backlog item.
- General encryption hardening for unrelated pre-existing plaintext fields (IMAP/SMTP passwords, WhatsApp tokens) is tracked separately and is not addressed by this feature.
- The verification step in User Story 1 is an operational/manual confirmation performed once per production deploy of the encryption keys, not a new automated dashboard or UI — no UI work is implied by this spec.
