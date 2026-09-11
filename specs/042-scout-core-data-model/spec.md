# Feature Specification: Scout Core & Data Model

**Feature Branch**: `042-scout-core-data-model`

**Created**: 2026-08-19

**Status**: Draft

**Input**: User description: "@docs/kanban/backlog/scout/01-core-and-data-model/spec62.md" (resolved to `docs/kanban/ciclo 9/scout/01-core-and-data-model/spec62.md`, Phase 1 of the Scout AI agent engine — see master doc `docs/kanban/ciclo 9/scout/spec60.md` §3, §4.3, §6, §9)

## Clarifications

### Session 2026-08-19

- Q: Should the `provider` field be restricted to a known set of supported LLM providers, or accepted as free text? → A: Restrict to an enum limited to `gemini`, `openai`, `anthropic` — reject anything else (including `openrouter`/`ollama`) at save time.
- Q: Should the system prevent a `Scout` from being linked to the same inbox more than once? → A: Enforce uniqueness on `inbox_id` in `ScoutInbox` — a Scout may serve many inboxes, but each inbox may be linked to at most one Scout at a time.
- Q: When a `Scout` is deleted, what should happen to its `ScoutInbox` associations and `ScoutTool` records? → A: Mirror Chatwoot's existing Captain feature convention — cascade-delete `ScoutInbox` (the pivot has no independent meaning once the Scout is gone), but do NOT cascade-delete `ScoutTool`, since tools are account-scoped and independent of any single Scout (matching how `Captain::Assistant` cascade-deletes its inbox pivot but never owns `Captain::CustomTool`, which belongs to `Account`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Provision a Scout AI agent for an account (Priority: P1)

An operator (account admin, via console/seeds in this phase — no UI yet) creates a Scout record for
an account, configuring which LLM provider and model it uses, its own API key, and which inbox(es)
it should be attached to. Once configured, the Scout can successfully complete a single tool-calling
round-trip against the real LLM provider, proving the multi-provider client integration works end to
end before any message-processing pipeline is built on top of it.

**Why this priority**: This is the foundation every later phase (native tools, pipeline processing,
UI) depends on. Without a working Scout record and a proven LLM client connection, no other Scout
capability can be built or verified.

**Independent Test**: Can be fully tested by creating a `Scout` via console/seed with a
`provider`/`model_name`/`api_key_override`, associating it to an inbox via `ScoutInbox`, and
confirming a manual tool-calling request against the provider succeeds — independent of any UI or
message pipeline.

**Acceptance Scenarios**:

1. **Given** an account with no Scouts, **When** an operator creates a `Scout` with a valid
   `provider`, `model_name`, and `api_key_override`, **Then** the record is persisted and can be
   associated with one or more inboxes via `ScoutInbox`.
2. **Given** a configured `Scout`, **When** the operator triggers a tool-calling request through the
   LLM client, **Then** the request completes a full round-trip against the real provider (request
   sent, tool-calling response received).

---

### User Story 2 - Keep Scout credentials safe at rest (Priority: P2)

Because Scouts and their external tools hold live API keys and third-party auth headers, an operator
needs certainty that these secrets are never persisted as plaintext, in this environment or any
other this fork is deployed to.

**Why this priority**: A leaked API key or webhook auth header is a direct security/compliance
exposure. This must hold before any Scout is used against real conversations or real customer data,
but it is secondary to proving the core client integration works (User Story 1).

**Independent Test**: Can be fully tested by attempting to write `api_key_override` on a `Scout` (or
`auth_headers` on a `ScoutTool`) in an environment without `ActiveRecord::Encryption` configured and
confirming the write raises instead of silently persisting plaintext; and by confirming the
underlying database column is not human-readable when encryption is configured correctly.

**Acceptance Scenarios**:

1. **Given** `ActiveRecord::Encryption` is configured, **When** a `Scout` is saved with an
   `api_key_override`, **Then** the value is stored encrypted at rest, not as plaintext.
2. **Given** `ActiveRecord::Encryption` is NOT configured, **When** code attempts to save a `Scout`
   with `api_key_override` or a `ScoutTool` with `auth_headers`, **Then** the save raises an error
   rather than silently persisting the value in plaintext.

---

### User Story 3 - Respect response quota groundwork before billing exists (Priority: P3)

An operator needs a Scout's usage to be checkable against a quota, even though no billing/subscription
enforcement exists yet, so that later phases (Fail-Safe handoff, future billing) have a stable field
and method to build on without another schema change.

**Why this priority**: Lowest priority of the three — this phase only needs the data shape and check
method to exist and behave correctly; actual enforcement (pausing a Scout, triggering handoff) is
built in a later phase.

**Independent Test**: Can be fully tested in isolation by calling `Scout#quota_available?` with
different combinations of `responses_quota` and `responses_consumed` values, with no dependency on
the LLM client or message pipeline.

**Acceptance Scenarios**:

1. **Given** a `Scout` with `responses_quota: -1`, **When** `quota_available?` is called regardless
   of `responses_consumed`, **Then** it returns `true`.
2. **Given** a `Scout` with a finite `responses_quota` and `responses_consumed` below it, **When**
   `quota_available?` is called, **Then** it returns `true`.
3. **Given** a `Scout` with a finite `responses_quota` and `responses_consumed` at or above it,
   **When** `quota_available?` is called, **Then** it returns `false`.

---

### Edge Cases

- What happens when an operator tries to create a `Scout` with a `provider` outside
  `gemini`/`openai`/`anthropic` (e.g., `openrouter`, `ollama`, a typo)? The save must be rejected
  with a validation error, not silently accepted.
- What happens when an operator tries to associate the same `Scout` with the same inbox twice, or
  tries to link a second `Scout` to an inbox that already has one? Both must be rejected — an inbox
  may be linked to at most one `Scout` at a time.
- What happens when a `Scout` is created with `responses_quota: 0`? `quota_available?` must return
  `false` immediately (no responses can be consumed).
- What happens when the LLM provider tool-calling request fails (invalid key, network error, quota
  exceeded on the provider side)? This phase only needs the client integration to surface the
  failure; handling it gracefully (fail-safe handoff) is explicitly out of scope until a later phase.
- What happens if a migration for `ichatr_scouts`, `ichatr_scout_inboxes`, or `ichatr_scout_tools` is
  rolled back after being applied? It must leave the schema exactly as it was before the migration
  ran, with no orphaned data.
- What happens to a `Scout`'s `ScoutInbox` associations and `ScoutTool` records when the `Scout` is
  deleted? `ScoutInbox` rows are removed along with the Scout (they have no independent meaning);
  `ScoutTool` records are NOT deleted, since they are account-scoped and may be reused by other
  Scouts.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow creating a `Scout` record scoped to an account, with `provider`,
  `model_name`, and `api_key_override` fields, plus a `responses_quota` (default `-1`, meaning
  unlimited) and `responses_consumed` (default `0`) pair for future quota enforcement.
- **FR-001a**: System MUST restrict `Scout#provider` to one of `gemini`, `openai`, or `anthropic`,
  rejecting the save (with a validation error) for any other value, including `openrouter` and
  `ollama`.
- **FR-002**: System MUST allow associating a `Scout` with one or more inboxes through a dedicated
  pivot record (`ScoutInbox`), without adding any new column to the core inbox table.
- **FR-002a**: System MUST enforce that each inbox is linked to at most one `Scout` at a time (a
  `Scout` may serve multiple inboxes, but an inbox may not be linked to more than one `Scout`
  simultaneously), rejecting a `ScoutInbox` save that would violate this.
- **FR-003**: System MUST allow creating a `ScoutTool` record scoped to an account, describing an
  external REST tool (name, description, endpoint, HTTP method, auth headers, parameter schema), for
  later use by the tool-calling pipeline — this phase only needs the data shape to exist.
- **FR-003a**: System MUST delete a `Scout`'s `ScoutInbox` associations when the `Scout` is deleted
  (the pivot has no independent meaning once the Scout is gone), but MUST NOT delete `ScoutTool`
  records when a `Scout` is deleted, since tools are account-scoped and independent of any single
  Scout — mirroring how Chatwoot's existing Captain feature cascade-deletes its assistant-to-inbox
  pivot but never owns its account-scoped custom tools.
- **FR-004**: System MUST resolve a `Scout`'s configured `provider`, `model_name`, and
  `api_key_override` into a working LLM client capable of making a tool-calling request, using the
  fork's existing multi-provider LLM dependency rather than a custom-built gateway.
- **FR-005**: System MUST encrypt `Scout#api_key_override` and `ScoutTool#auth_headers` at rest,
  unconditionally — there is no environment-based bypass of encryption for these fields.
- **FR-006**: System MUST raise an error (rather than silently persisting plaintext) when code
  attempts to save `api_key_override` or `auth_headers` in an environment where the encryption
  dependency isn't configured.
- **FR-007**: System MUST provide a `Scout#quota_available?` check that returns `true` when
  `responses_quota` is `-1` (unlimited) or when `responses_consumed` is below a finite
  `responses_quota`, and `false` once `responses_consumed` reaches or exceeds a finite
  `responses_quota`.
- **FR-008**: System MUST add an optional `lost_reason` field to the existing Opportunity data model,
  in preparation for a later phase's stage-move tooling, without altering any core (non-custom)
  table.
- **FR-009**: All new tables and columns introduced by this feature MUST live under the fork's own
  namespace (`ichatr_` prefix) and MUST NOT modify any core Chatwoot table.
- **FR-010**: Database migrations for this feature MUST apply cleanly to a fresh database and MUST
  roll back cleanly, leaving no partial schema state.

### Key Entities

- **Scout**: An AI agent configuration scoped to an account — holds its persona/system prompt, which
  LLM provider/model/credential it uses, pipeline-stage routing hints for later phases, quota
  tracking (`responses_quota`, `responses_consumed`), and an enabled/active flag. One Scout can serve
  multiple inboxes.
- **ScoutInbox**: The association between a `Scout` and a core `inbox`, allowing one Scout to be
  active on several inboxes without changing the core inbox schema. Each inbox may be linked to at
  most one Scout at a time. Deleted automatically when its `Scout` is deleted.
- **ScoutTool**: An externally-callable REST tool definition scoped to an account (endpoint, HTTP
  method, authentication headers, parameter schema) that a Scout can be enabled to call in a later
  phase. Independent of any single Scout's lifecycle — not deleted when a Scout that used it is
  deleted.
- **Opportunity (extended)**: The existing Kanban opportunity record gains an optional `lost_reason`
  field, used by a later phase's stage-move tooling to record why a lead was disqualified.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator can provision a new Scout (record + inbox association) and confirm a
  successful tool-calling round-trip against a real LLM provider using only console/seed commands, in
  a single sitting, with no code changes required beyond configuration.
- **SC-002**: 100% of stored `api_key_override` and `auth_headers` values are unreadable as plaintext
  when inspected directly in the database.
- **SC-003**: 0% of attempts to persist `api_key_override` or `auth_headers` without encryption
  configured succeed silently — all such attempts are rejected with an error.
- **SC-004**: `Scout#quota_available?` produces the correct true/false result for 100% of tested
  quota/consumption combinations (unlimited, under quota, at quota, over quota).
- **SC-005**: The full migration set for this feature applies and rolls back on a fresh database with
  zero manual intervention or cleanup required.

## Assumptions

- This phase has no user-facing UI; a Scout, its inbox associations, and its tools are created and
  verified via console or seed scripts only. UI is deferred to a later phase.
- No message-processing job, debounce buffer, or automated pipeline exists yet in this phase; the
  "tool-calling round-trip" acceptance criteria is proven manually (console/spec), not through live
  conversation traffic.
- No native Ruby tools (`manage_opportunity`, `handover_to_human`, etc.) are implemented in this
  phase — only the data model and LLM client integration that later tools will depend on.
- No billing/subscription enforcement exists yet; `responses_quota` is set manually per Scout, and
  `-1` (unlimited) is the expected default for test/dev accounts and accounts without active billing.
- The fork's existing multi-provider LLM dependency is used directly for provider calls; no custom
  gateway/abstraction is built for this phase beyond what's needed to instantiate a client from a
  Scout's stored configuration.
- Encryption configuration itself (e.g., resolving missing keys in a production deployment) is
  handled by a separate, later phase — this phase only needs to guarantee that writes fail safely
  when encryption isn't available, not to configure encryption for every environment.
