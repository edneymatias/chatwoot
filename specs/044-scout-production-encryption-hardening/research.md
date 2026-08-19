# Research: Scout Production Encryption Hardening

## 1. Whether FR-004–FR-007 (fail-loudly guard) require new application code

**Decision**: No new Ruby/Rails guard code is needed. FR-004 through FR-007 are already fully
satisfied by the Phase 1 implementation (`specs/042-scout-core-data-model`).

**Rationale**: `custom/app/models/scout.rb` calls `encrypts :api_key_override` and
`custom/app/models/scout_tool.rb` calls `encrypts :auth_headers` **unconditionally** — with no
`if Chatwoot.encryption_configured?` guard, unlike every other encrypted-credential model in this
codebase (see `specs/042-scout-core-data-model/research.md` §2 for that prior decision and its
rationale). Rails' `ActiveRecord::Encryption` itself raises
`ActiveRecord::Encryption::Errors::Configuration` on save whenever an `encrypts`-declared
attribute is written and no encryption key is configured for the current environment. Combined
with the environment-scoped default behavior in finding #2 below, this means:
- In `RAILS_ENV=production` with no `ACTIVE_RECORD_ENCRYPTION_*` env vars set, any attempt to
  persist a `Scout`/`ScoutTool` with a populated `api_key_override`/`auth_headers` already raises
  today — satisfying FR-004/FR-005 (`fail loudly, not silently persist plaintext`) with existing
  code.
- Saves that don't touch the sensitive field, or happen outside production, already succeed —
  satisfying FR-006.
- The raise is driven by the same three `ACTIVE_RECORD_ENCRYPTION_*` values that
  `Chatwoot.encryption_configured?` (`config/application.rb:106`) checks, so there is no second,
  divergent notion of "configured" — satisfying FR-007's intent even though the guard is Rails'
  own encryption machinery rather than an explicit call to `Chatwoot.encryption_configured?`.
- `custom/spec/models/scout_spec.rb` (`'fails closed when encryption keys are not configured'`)
  and `custom/spec/models/scout_tool_spec.rb` (same test name) already assert this exact behavior
  and pass in CI today.

**Alternatives considered**:
- Add an explicit `before_save` guard calling `Chatwoot.encryption_configured?` and raising a
  custom error — rejected as redundant per the Phase 1 research decision it would duplicate, and
  against the "Smallest Production-Ready Change" constitution principle (no code needed to satisfy
  a requirement that is already met).
- Add new regression specs for FR-004–FR-007 — rejected as duplicating existing, passing coverage
  in `scout_spec.rb`/`scout_tool_spec.rb`; this plan instead treats those specs as the acceptance
  evidence for FR-004–FR-007 and does not touch them unless a gap is found during implementation.

## 2. Why dev/test environments don't need explicit keys (User Story 3)

**Decision**: No change needed to make User Story 3 true — it already holds today.

**Rationale**: Rails 7.1's `ActiveRecord::Encryption` railtie auto-provisions a fixed, insecure
default key set (`primary_key: 'test-primary-key-32-chars-length'` and matching deterministic
key/salt) for `development` and `test` environments specifically so encrypted columns work out of
the box without real key management. This is why `custom/spec/models/scout_spec.rb`'s "fails
closed" test has to explicitly `nil` out `ActiveRecord::Encryption.config.primary_key` to simulate
the unconfigured state — under normal test-environment boot, a key is already present. Rails does
**not** provide this fallback in `production`, which is exactly the environment boundary FR-004-007
need. No repo code change is required for this behavior; it is a Rails framework default already
in effect.

**Alternatives considered**: None — this is existing framework behavior, not a design decision
this feature makes.

## 3. Key delivery mechanism for the production Swarm stack (FR-001)

**Decision**: Add the three `ACTIVE_RECORD_ENCRYPTION_*` variables as explicit `environment:`
entries (blank placeholders, following the existing `POSTGRES_PASSWORD=` pattern) to the `rails`
and `sidekiq` service blocks in the repo-tracked `docker-compose.production.yaml`, with a comment
directing the operator to either fill them in directly or supply them via a Docker Swarm secret
instead — consistent with the clarified answer that either mechanism is acceptable, operator's
choice.

**Rationale**: `docker-compose.production.yaml`'s `base` anchor only sets `env_file: .env`, which
`docker stack deploy` does not process reliably (confirmed in spec61.md and spec64.md) — so the
three keys must appear under an actual `environment:` list to be honored under Swarm, matching how
`RAILS_ENV`/`NODE_ENV`/`INSTALLATION_ENV` are already declared per-service rather than via
`env_file`. The `rails` and `sidekiq` services both need them (Sidekiq jobs read/write `Scout`
records too), so the same three lines are added to both `environment:` blocks rather than lifted
into the shared `base` anchor — YAML merge-key semantics (`<<: *base`) make a child's own
`environment:` list fully replace (not merge into) the anchor's list, and `rails`/`sidekiq` already
each define their own `environment:` block, so adding to `base` would silently disappear.

**Alternatives considered**:
- Mandate Docker Swarm secrets only — rejected per the clarified spec answer (operator's choice).
- Restructure the `base`/`rails`/`sidekiq` anchor merge to share a single `environment:` list —
  rejected as an unrelated refactor of a working file structure, against the "Smallest
  Production-Ready Change" principle.
- Leave `docker-compose.production.yaml` untouched and only document the requirement in prose —
  rejected because the tracked file is the actual template operators copy for their (external)
  Swarm stack; leaving `env_file: .env` as the only vehicle would reproduce the exact bug spec61.md
  identifies.

## 4. Verification mechanism for FR-002/FR-003 (operator confirmation)

**Decision**: Document the verification as a `bin/rails runner` one-liner against the running
production `rails` service/container (checking `Chatwoot.encryption_configured?`, then creating,
reloading, and deleting a throwaway `Scout` to prove round-trip encryption) rather than building a
new rake task, script, or UI.

**Rationale**: `Chatwoot.encryption_configured?` already exists and is the exact predicate FR-002
needs surfaced; wrapping it in a new rake task or console command would be code whose only purpose
is to call one already-public class method, which the "Smallest Production-Ready Change" principle
rejects (no caller today needs a scripted version — this is a one-time-per-deploy manual
operator step, not a recurring/automated check). The quickstart validation guide
(`quickstart.md`) documents the exact commands.

**Alternatives considered**:
- A dedicated rake task (e.g. `rails scout:verify_encryption`) — rejected as unjustified
  abstraction over a single existing boolean method for a manual, infrequent operator action.
- A Super Admin UI panel showing encryption status — rejected as disproportionate scope for an
  ops-only verification need with no other UI precedent requested by the source spec.
