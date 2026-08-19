# Data Model: Scout Production Encryption Hardening

## Summary

This feature introduces **no new entities, columns, or migrations**. It reuses the `Scout` and
`ScoutTool` models delivered in Phase 1 (`specs/042-scout-core-data-model`) unchanged.

## Entities (existing, referenced only)

### Scout (`ichatr_scouts`, `custom/app/models/scout.rb`)

Field of interest: `api_key_override` (string, `encrypts` unconditionally — see
[research.md](research.md) §1). No schema or validation change required by this feature.

### ScoutTool (`ichatr_scout_tools`, `custom/app/models/scout_tool.rb`)

Field of interest: `auth_headers` (jsonb, `encrypts` unconditionally — see
[research.md](research.md) §1). No schema or validation change required by this feature.

## Non-data deliverables

This feature's actual changes live outside the data model:
- `docker-compose.production.yaml` — deployment configuration (see research.md §3).
- `specs/044-scout-production-encryption-hardening/quickstart.md` — operator verification runbook
  (see research.md §4).

No `contracts/` are produced: this feature exposes no new API endpoint, CLI command, or UI
surface — it is a deployment-configuration and operational-verification change only.
