# Phase 1 Data Model: Scout Deterministic Router and Conversation Routing State

## Routing Snapshot (`Custom::ScoutV2::RoutingSnapshot`)

Immutable value object, one instance per turn attempt (FR-001). `Data.define`-style with a
keyword-only custom `initialize` (same pattern as brief 01's `Playbook`), so it is directly
constructible in a spec with no database and no language model (FR-003). Renamed and expanded from
brief 01's two-field `RoutingContext` seed (research.md D1).

| Field | Type | Default when omitted | Notes |
|---|---|---|---|
| `conversation` | `Conversation \| nil` | `nil` | not read by any predicate this phase, carried for later phases |
| `contact` | `Contact \| nil` | `nil` | same |
| `inbox` | `Inbox \| nil` | `nil` | same |
| `scout` | `Scout \| nil` | `nil` | same |
| `opportunity` | `Opportunity \| nil` | `nil` | read by `opportunity_open` (brief 01, unchanged) |
| `opportunity_stage_role` | `Symbol` (`:initial \| :qualified \| :unqualified \| :none`) | `:none` | derived by the Builder (research.md D3); `:none` both when the opportunity has no matching stage and when there is no opportunity at all |
| `pending_fields` | `Array<String>` | `[]`, never `nil` | read by `pending_required_fields` (brief 01, unchanged); derived by the Builder (research.md D4) |
| `active_playbook` | `Custom::ScoutV2::Playbook \| nil` | `nil` | the **resolved object**, not a name (research.md D5) — read by `Router` for continuity/priority comparison |
| `transitions` | `Integer` | `0` | turn-scoped transition-hand-off count so far this attempt (FR-001/FR-016) — supplied by the caller, never derived from persisted state (research.md D6) |
| `satisfied_capabilities` | `Array<String>` | `[]`, never `nil` | pass-through only this phase; no predicate reads it, no capability is resolved/exercised (spec Assumptions) |

**Construction rule**: every field is independently overridable via keyword args; omitted keys take
the defaults above (mirrors `Playbook#initialize`'s `attrs[:key] || default` pattern) — so existing
brief-01 tests that only ever supplied `opportunity:`/`pending_fields:` keep working unchanged
after the rename.

## Routing Snapshot Builder (`Custom::ScoutV2::RoutingSnapshot::Builder`)

The one component in this phase allowed to touch the database (FR-002 forbids everything else —
`Router`, the predicates — from doing so). Not itself a spec Key Entity; the concrete assembly step
FR-001 requires "the system" to perform.

| Member | Signature | Behavior |
|---|---|---|
| `.call` | `(conversation:, catalog:, turn_transition_count: 0) -> RoutingSnapshot` | assembles one snapshot for the given conversation |

Resolution per field, all via existing associations/records — no new query patterns invented:

- `contact` ← `conversation.contact`
- `inbox` ← `conversation.inbox`
- `scout` ← `conversation.inbox&.scout` (existing `has_one :scout, through: :scout_inbox`)
- `opportunity` ← `conversation.active_opportunity` (existing `has_one`, `foreign_key:
  active_conversation_id`)
- `opportunity_stage_role` ← computed from `scout`'s three stage-id columns vs.
  `opportunity.pipeline_stage_id`, `:none` if either `scout` or `opportunity` is absent or the
  stage matches none of the three (research.md D3)
- `pending_fields` ← union of `scout.required_custom_attribute_definitions` and
  `opportunity.pipeline_stage.required_custom_attribute_definitions`, filtered to those blank in
  `opportunity.custom_attributes`, mapped to `attribute_key`; `[]` if there is no `opportunity`
  (research.md D4)
- `active_playbook` ← `catalog.find_by_name(ScoutConversationState.for_conversation(conversation).active_playbook)`
  (`nil`-safe both when there is no persisted state row and when the name doesn't resolve —
  research.md D5/D9)
- `transitions` ← `turn_transition_count` argument, verbatim
- `satisfied_capabilities` ← `[]` this phase (no `CapabilityRegistry` exists yet — brief 07)

## Router (`Custom::ScoutV2::Router`)

Stateless decision component (spec Key Entity "Router"). Pure function of its two arguments — no
I/O, no LLM call (FR-002, SC-001).

| Member | Signature | Behavior |
|---|---|---|
| `.call` | `(ctx, catalog) -> Router::Decision` | the state-based half of activation only |

Decision rule (research.md D7), evaluated once:

1. `winner = catalog.ordered_by_priority.find { |pb| pb.when_state.present? && Predicates::Evaluator.call(pb.when_state, ctx) }`
   — highest-priority playbook whose `when_state` fully matches `ctx`; playbooks with no
   `when_state` are never candidates (FR-013); no tie-break needed, priority is already unique
   (FR-006, brief-01 boot validation).
2. `active = ctx.active_playbook`
3. Selection: `winner.nil? → active` (FR-011, or `nil` if `active` is also `nil` → FR-012) · `active.nil? || winner.name == active.name → winner` (FR-007/FR-008) · `winner.priority > active.priority → winner` (FR-009, interruption) · else `→ active` (FR-010).
4. `confidence = selected.nil? ? nil : 1.0`.

### Router Decision (`Custom::ScoutV2::Router::Decision`)

Nested value object (no separate file — mirrors `Validator::ValidationError`'s nesting precedent).

| Field | Type |
|---|---|
| `playbook` | `Custom::ScoutV2::Playbook \| nil` |
| `confidence` | `Float \| nil` — `1.0` when `playbook` is present, `nil` for "no playbook selected by state" (FR-012) |

`Router` never writes to the database, never distinguishes "continuing unchanged" from "freshly
activated" in its return value — a caller that already has `ctx.active_playbook` can tell the two
apart itself by comparing `decision.playbook`'s name against it (no duplicate state needed on
`Decision`). Persisting the resulting activation (FR-014) is the caller's responsibility via
`ScoutConversationState`, not `Router`'s — see spec Key Entities: "[Router] ... never itself
performs a transition hand-off, which is a playbook-ending mechanism, not a router decision."

## Conversation Routing State (`ScoutConversationState`, table `ichatr_scout_conversation_states`)

Persisted, one row per conversation (spec Key Entity "Conversation Routing State"). Flat,
unnamespaced AR model (research.md D10).

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| `id` | bigserial | no | — | |
| `account_id` | bigint | no | — | FK `accounts`, `on_delete: :cascade`; query-scoping parity with sibling `ichatr_*` tables (research.md D11) |
| `conversation_id` | bigint | no | — | FK `conversations`, `on_delete: :cascade`; **unique** — one row per conversation |
| `active_playbook` | string | yes | `nil` | playbook **name** (not a FK — playbooks are files, brief 01); `nil` = no playbook currently active |
| `activated_at` | datetime | yes | `nil` | when `active_playbook` was last set by any of the three writer methods below |
| `activation_reason` | integer (`enum`) | yes | `nil` | `state: 0`, `trigger: 1` (unused this phase, FR-014 reserves it), `transition: 2` |
| `transition_count` | integer | no | `0` | **cumulative historical** count, incremented only by `record_transition!`; never the turn-scoped limit's input (FR-021) |
| `handoff_limit_reached_at` | datetime | yes | `nil` | set only when a 3rd hand-off is refused within one turn attempt; overwritten (never reset/accumulated) by a later occurrence (FR-018) |
| `last_exit` | string | yes | `nil` | name of the most recent **terminal** ending; untouched by state activation or transition hand-off (FR-020); only ever replaced by a later terminal ending (FR-019/clarification #3) |
| `unsatisfied_flags` | jsonb | no | `{}` | reserved for a later phase's use (spec Assumptions); created but never populated/read by this phase's code |
| `created_at` / `updated_at` | datetime | no | — | standard Rails timestamps |

**Validations**: `account_id`/`conversation_id` presence; `conversation_id` uniqueness (defense in
depth alongside the DB unique index); `transition_count` numericality (integer, `>= 0`).

**Instance methods** (research.md D8 — three intention-revealing writers, no generic "apply"
method; behavior verified directly against DB records per Constitution VII, not mocked):

| Method | Signature | Effect | Return |
|---|---|---|---|
| `record_state_activation!` | `(playbook_name)` | `active_playbook = playbook_name`, `activated_at = Time.current`, `activation_reason = :state`; `last_exit` untouched | the record |
| `record_transition!` | `(target_playbook_name, turn_transition_count:)` | if `turn_transition_count >= 2`: only `handoff_limit_reached_at = Time.current`, nothing else changes, refused; else: `active_playbook = target_playbook_name`, `activated_at = Time.current`, `activation_reason = :transition`, `transition_count += 1`; `last_exit` untouched either way | `true` if performed, `false` if refused |
| `record_terminal_exit!` | `(exit_name)` | `active_playbook = nil`, `activated_at = nil`, `activation_reason = nil`, `last_exit = exit_name` (replaces prior value) | the record |

**Class method**: `ScoutConversationState.for_conversation(conversation)` —
`find_or_initialize_by(conversation_id:)`, never forces a write (research.md D9); used by
`RoutingSnapshot::Builder` and available to any later-phase caller needing "this conversation's
current routing state, creating nothing on a mere read."

## Activation Reason (`ScoutConversationState#activation_reason` enum)

Spec Key Entity, represented purely as the column's Rails enum — no separate class.

| Value | Produced by | Counts toward the 2-per-turn cap (FR-016/FR-017)? |
|---|---|---|
| `state` | `Router` decisions (fresh activation **and** priority interruption alike — clarification #1), persisted via `record_state_activation!` | never — the router runs at most once per turn attempt, so it can never itself reach the cap |
| `trigger` | not produced by this phase's code (brief 04) | n/a this phase |
| `transition` | a playbook's own declared "transition" ending, persisted via `record_transition!` | yes — the only reason that does |

## Playbook Ending (conceptual only this phase — no new class)

Spec Key Entity "Playbook Ending." What triggers a playbook to reach a "transition" or "terminal"
ending during a live turn is explicitly out of scope (brief 03's `TurnRunner`, per spec
Assumptions). This phase defines only what happens to persisted state once one is reached — i.e.
exactly `record_transition!`/`record_terminal_exit!` above. No `Ending`/`TransitionEnding`/
`TerminalEnding` Ruby type is introduced; a later phase's "playbook reached its `exits.<name>`
ending" mechanism calls these two methods directly with the target/exit name it already has from
the playbook's own frontmatter (brief 01's `Playbook#exits`).
