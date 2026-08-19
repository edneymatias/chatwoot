# Phase 03 — Production Hardening (Encryption Gate)

**Master doc**: `docs/kanban/backlog/scout/spec60.md` §3.2, §9
**Depends on**: Phase 01 (encrypted fields exist in the schema).
**Blocks**: Phase 04 onward in production — no Scout writing real `api_key_override`/
`auth_headers` should run against a production environment until this phase closes.

## Goal

Guarantee `ActiveRecord::Encryption` is actually configured and enforced wherever Scout runs in
production, closing the gap identified in
[`docs/kanban/backlog/11-production-secrets-encryption-hardening/spec61.md`](../../11-production-secrets-encryption-hardening/spec61.md).

## Scope

- Resolve `docs/kanban/backlog/11-production-secrets-encryption-hardening/spec61.md` items 1-4 as they apply
  to the Scout rollout specifically:
  - Generate the three `ACTIVE_RECORD_ENCRYPTION_*` keys (`bin/rails db:encryption:init`).
  - Get them into the production Docker Swarm stack (Swarm secrets or explicit `environment:`
    entries — `env_file:` is unreliable under `docker stack deploy`).
  - Confirm `Chatwoot.encryption_configured?` returns `true` in the actual production deployment,
    not just locally.
- Add a boot-time or deploy-time check specific to Scout: if `RAILS_ENV=production` and
  `Chatwoot.encryption_configured?` is `false`, prevent `Scout`/`ScoutTool` records from being
  created with `api_key_override`/`auth_headers` populated (fail loudly, not silently persist
  plaintext).

## Out of scope

- General encryption backfill for pre-existing plaintext fields (IMAP/SMTP passwords, WhatsApp
  tokens) — tracked separately in backlog item 11, not a Scout-specific concern.
- Key rotation, external KMS/Vault integration — explicitly out of scope per backlog item 11.

## Acceptance criteria

- Production Swarm stack has the three encryption keys configured and verified working (a
  `Scout`/`ScoutTool` created in production round-trips `api_key_override`/`auth_headers` through
  encryption correctly).
- Attempting to create a `Scout` with `api_key_override` set in a production environment lacking
  encryption keys fails loudly instead of persisting plaintext.
