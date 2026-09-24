# Phase 01 — Core & Data Model

**Master doc**: `docs/kanban/backlog/scout/spec60.md` §3, §6, §9
**Depends on**: nothing — this is the foundation phase.

## Goal

Land the Scout data model under `custom/` and wire up `ruby_llm` as the multi-provider LLM
client — enough to instantiate a `Scout`, attach it to an inbox, and make a single tool-calling
request through a provider, with no message-processing pipeline yet.

## Scope

- New models under `custom/app/models/`, flat classes (no `Ai::`/`Scout::` module nesting, matching
  the `Opportunity`/`PipelineStage` convention):
  - `Scout` (table `ichatr_scouts`) — see spec60.md §9.1 for the full field list, including
    `responses_quota` (default `-1`) / `responses_consumed` (default `0`) and `encrypts
    :api_key_override`.
  - `ScoutInbox` (table `ichatr_scout_inboxes`) — pivot to `inbox_id`, no column added to core
    `inboxes`.
  - `ScoutTool` (table `ichatr_scout_tools`) — see spec60.md §9.3, `encrypts :auth_headers`.
- New migrations under `db/migrate/`, following the fork's existing convention: far-future
  timestamp prefix (`21260...`), `ichatr_` table prefix (mirror
  `21260730224301_create_ichatr_opportunities.rb`).
- New migration adding `lost_reason` (string, optional) to `custom/app/models/opportunity.rb`'s
  table (`ichatr_opportunities`) — required by Phase 02's `move_opportunity_stage` tool, landed
  here since it's a schema change.
- `Scout#quota_available?` method (`responses_quota == -1 || responses_consumed < responses_quota`).
- Integrate the already-vendored `ruby_llm` gem (`Gemfile:201-202`, resolved `1.15.0`) as the LLM
  client — no custom multi-provider gateway code. A `Scout` resolves its `provider`/`model_name`/
  `api_key_override` into a `RubyLLM` client instance capable of tool-calling.
- Encryption is **mandatory** for `api_key_override` and `auth_headers` — no `if
  Chatwoot.encryption_configured?` guard bypass. This creates a hard dependency: these fields
  cannot be safely written in an environment where `ActiveRecord::Encryption` isn't configured. See
  Phase 03.

## Out of scope (deferred to later phases)

- No message-processing job, debounce, or Redis buffer (Phase 02 territory in the reordered
  roadmap — see spec60.md §11 for phase numbering).
- No native Ruby tools (`manage_opportunity`, `handover_to_human`, etc.) — this phase only proves
  the LLM client can make a tool-calling request, not that Scout tools exist yet.
- No UI — `Scout`/`ScoutInbox`/`ScoutTool` are created via console/seeds only in this phase.
- No billing/subscription validation — `responses_quota` is set manually (`-1` for unlimited
  testing) per spec60.md §4.3. This phase does not decide *who* sets the quota in production.

## Acceptance criteria

- A `Scout` record can be created with a `provider`/`model_name`/`api_key_override`, associated to
  one or more inboxes via `ScoutInbox`, and can successfully complete a single tool-calling
  round-trip through `ruby_llm` against a real provider (manually verified, e.g. via console/spec).
- `api_key_override` and `auth_headers` are stored encrypted at rest; writing them in an
  environment without `ActiveRecord::Encryption` configured raises rather than silently persisting
  plaintext.
- `Scout#quota_available?` returns `true` for `responses_quota: -1` regardless of
  `responses_consumed`, and `false` once `responses_consumed >= responses_quota` for a finite quota.
- Migrations run cleanly on a fresh DB and roll back cleanly.
