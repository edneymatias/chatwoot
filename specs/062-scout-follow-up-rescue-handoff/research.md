# Research: Scout Follow-Up Nudges and Rescue Handoff

All technical unknowns below were resolved by reading the current state of the codebase (the
source design doc, `docs/kanban/ciclo 10/scout/22-scout-follow-up-nudges-and-rescue-handoff/spec85.md`,
was written against a slightly earlier snapshot — the deviations found are called out explicitly
so the plan reflects what's actually in the tree today, not what the doc assumed).

## Migration style for `ichatr_scouts`

- **Decision**: Use explicit `up`/`down` methods with `change_table :ichatr_scouts, bulk: true`
  for the new columns, plus a separate `add_index` and `add_foreign_key ... on_delete: :nullify`
  call for `rescue_stage_id` — matching `db/migrate/21260819000005_add_pipeline_fields_to_ichatr_scouts.rb`
  exactly (the migration that introduced `qualified_stage_id`/`unqualified_stage_id`/`handover_team_id`).
- **Rationale**: This is the fork's established migration convention for this table (also used in
  the more recent `21260828230000_add_response_auditor_flag...` and
  `21260902140000_add_default_phone_locale...` migrations) — `ActiveRecord::Migration[7.0]` with
  `up`/`down`, not `change`.
- **Alternatives considered**: `spec85.md`'s own snippet (`ActiveRecord::Migration[7.1]`, `change`
  method, `add_reference ... foreign_key: { to_table:, on_delete: }` shorthand). Rejected —
  functionally equivalent but inconsistent with every other Scout migration in the tree; per
  Constitution Principle III (Adhere to Established Conventions), match the existing pattern
  rather than introducing a second migration style for the same table.

## Fixed attempt count vs. configurable thresholds

- **Decision**: `follow_up_delays_hours` must validate as an array of **exactly 3** ascending,
  unique, positive integers, not merely "non-empty ascending positive." Positions 0/1 are the two
  re-engagement thresholds; position 2 is the handoff threshold.
- **Rationale**: `/speckit-analyze` flagged that the source design's decision "2 nudges, fixed,
  not configurable this phase" (spec85.md decision 1) and the array-based configurable-cadence
  decision (spec85.md decision 5) were only reconciled by convention (a 3-element default), not by
  an enforced constraint — an account could otherwise submit a 4-or-more-element array and silently
  get a 3rd nudge before handoff, contradicting the fixed-attempt-count decision. Adding the length
  check to the model validation closes that gap without touching the job's indexing logic
  (`delays[attempts]`, `attempts < delays.size - 1`), which already assumed a 3-element array.
- **Alternatives considered**: Dropping the "fixed at 2" constraint and letting array length freely
  determine attempt count. Rejected — that was a deliberate, explicit product decision in the
  source doc (mirroring the "no LLM in business-critical transitions" precedent from `spec80.md`),
  not an oversight; the fix is to enforce it, not remove it.

## Rescue-stage and open-opportunity guards apply to nudges too, not just the handoff

- **Decision**: The `scout.rescue_stage_id.blank?` check and the "conversation has an open linked
  opportunity" check both happen once, at the top of per-Scout / per-conversation processing,
  before any threshold comparison — so they gate nudges (FR-001/FR-002) exactly as much as the
  rescue handoff (FR-003).
- **Rationale**: `/speckit-analyze` found that an earlier task breakdown described these two
  guards only under the rescue-handoff user story, which would have let an MVP-only deployment
  (User Story 1 alone) send nudges to accounts without a configured rescue stage, or on
  conversations with no open deal — contradicting FR-007 and FR-010, both of which say "this
  automation" (not "the handoff") is what's gated.
- **Alternatives considered**: Gating only the handoff (as the flagged task breakdown did).
  Rejected — directly contradicts the plain reading of FR-007/FR-010, and would mean the "MVP
  first" delivery path in `tasks.md` ships behavior the spec explicitly prohibits.

## Deriving follow-up attempt count without a counter column

- **Decision**: Count outgoing, non-private messages with `content_attributes['scout_follow_up'] == true`
  in the trailing run of outgoing messages since the last incoming message (i.e.
  `messages.order(created_at: :desc).take_while { |m| !m.incoming? }`).
- **Rationale**: `Message#content_attributes` is a plain JSON column (`store :content_attributes,
  accessors: [...], coder: JSON` in `app/models/message.rb`) — `store` only generates convenience
  accessor methods for the listed keys, it does not restrict what can be written into or read from
  the underlying hash, so writing/reading `content_attributes['scout_follow_up']` for a key not in
  the accessor list works exactly like any other hash key. This avoids a new counter column/migration
  (Constitution II) and confirms the source doc's approach is valid as designed against the current schema.
- **Alternatives considered**: A new `follow_up_attempts` integer column on the conversation or
  opportunity. Rejected by the source design (and reaffirmed here) — would drift out of sync with
  reality if a run is skipped (e.g., out-of-office) and adds migration/lifecycle surface for
  information already derivable from existing data.

## Business-hours guard

- **Decision**: Call `conversation.inbox.out_of_office?` (from the core `OutOfOffisable` concern,
  `app/models/concerns/out_of_offisable.rb`) and skip the nudge/handoff for that run if true,
  leaving the conversation to be re-evaluated on the next 30-minute cycle.
- **Rationale**: `OutOfOffisable#out_of_office?` is `working_hours_enabled? && working_hours.today.closed_now?`
  — accounts without working hours configured already return `false` unconditionally, so no
  special-casing is needed for that case (confirms spec Assumption "no business hours configured
  ⇒ always within business hours").
- **Alternatives considered**: none — this is already the correct, existing mechanism and is
  reused read-only exactly as `system_prompts_service.rb` does for its own unrelated notice.

## Race-window handling (two places)

- **Decision (FollowUpJob)**: Re-check `conversation.pending?` (uncached read) immediately before
  sending a nudge or performing the rescue handoff, inside `process_conversation`, in addition to
  the coarse `last_activity_at < cutoff` SQL scan. `HandoffService#perform_handoff` already
  re-checks `pending?` a second time immediately before its own message send + `bot_handoff!`, so
  the handoff path has two independent checks; nudges only need the one in the job since nudges
  don't call `HandoffService`.
- **Decision (AgentRunner)**: Add one additional `return unless conversation_pending?` in
  `process_audited_reply`, right after the response auditor call returns and before
  `dispatch_outgoing_reply`/`trigger_handoff` — closing the gap between the last existing recheck
  (top of `process_response`, line 77) and the LLM-backed auditor call, which can take long enough
  for a human or the contact to act in the meantime.
- **Rationale**: Every recheck reads `Conversation.uncached { ... }.pick(:status)`, the same
  pattern already used four times in the codebase (`AgentRunner#conversation_pending?`,
  `HandoffService#perform_handoff`) — reusing that exact idiom rather than introducing a new
  helper avoids duplicating the "why uncached" invariant in two forms.
- **Alternatives considered**: Locking the conversation row for the duration of the auditor call.
  Rejected — the auditor call is an LLM round-trip (unbounded latency), so holding a lock across it
  risks starving the legitimate path (a human or the contact acting) that this fix exists to protect.

## `Opportunity#scout_engaged?` and the Kanban badge

- **Decision**: `active_conversation&.pending? && active_conversation.inbox&.scout&.enabled? || false`,
  exposed as `as_json['scout_engaged']`; `KanbanCard.vue` renders the badge `v-if="opportunity.scout_engaged"`,
  positioned beside the existing status badge (which is only shown for non-`open` status), so the
  two badges never visually compete for the same slot on an open deal.
- **Rationale**: The inverse lookup `inbox.scout` already exists (`custom/app/models/custom/concerns/inbox.rb`:
  `has_one :scout_inbox` + `has_one :scout, through: :scout_inbox`), so `scout_engaged?` needs no
  new association — it's a pure read of existing `Conversation#pending?`, `Inbox#scout`, and
  `Scout#enabled?`.
- **Alternatives considered**: Deriving the badge from a `FollowUpJob`-side flag/timestamp written
  onto the opportunity. Rejected — would duplicate state that's already fully derivable from
  `conversation.status` + `inbox`'s Scout wiring, and would need its own invalidation on handoff.
