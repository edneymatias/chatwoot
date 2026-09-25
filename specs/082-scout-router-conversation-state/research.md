# Phase 0 Research: Scout Deterministic Router and Conversation Routing State

Technical Context in plan.md left no `NEEDS CLARIFICATION` markers — the three spec clarifications
(2026-09-24 session) resolved the only genuinely ambiguous product questions (interruption's
activation reason, the limit-reached marker, reactivation leaving `last_exit` untouched). The
remaining unknowns are implementation-mechanism decisions, resolved below against `design.md`
§4.4/§6, brief 02, and the concrete brief-01 code already in the repo.

## D1 — Rename `RoutingContext` → `RoutingSnapshot` (in-place cutover, not a new type)

**Decision**: Rename `custom/app/services/custom/scout_v2/routing_context.rb` (defining
`Custom::ScoutV2::RoutingContext`) to `routing_snapshot.rb` (defining
`Custom::ScoutV2::RoutingSnapshot`), expanding its fields in the same change. Update the three
brief-01 spec files that reference the old name
(`predicates/evaluator_spec.rb`, `predicates/opportunity_open_spec.rb`,
`predicates/pending_required_fields_spec.rb`) to the new one. Brief 01's own `data-model.md`/
`research.md`/`quickstart.md`/`tasks.md` are historical records of what shipped at the time and
are **not** edited — they remain accurate about brief 01, not about the class's current name.

**Rationale**: `spec.md`'s Key Entities section names this exact entity "Routing Snapshot"
throughout, and FR-001/FR-003 use that term, not "context." This is the same struct brief 01 seeded
as a deliberately minimal placeholder — research.md D8 of that phase said explicitly "brief 02 is
expected to *extend* this struct's fields (additive), not replace it." Extending it here is exactly
that predicted evolution, and keeping the code's name aligned with the spec's canonical term now
(while this exact file is already being substantially rewritten) avoids permanent drift between
what every future brief's docs call it and what the code calls it. Constitution's "don't rename
files that exist upstream" doesn't apply — this file has no upstream equivalent; it is a
same-repo, same-phase-family rename of a fork-original file being extended in place, not a
drive-by rename of unrelated code (Constitution II).

**Alternatives considered**: Keep the class named `RoutingContext` and just add fields — rejected,
permanently commits every later brief (03 `TurnRunner`, 04 `open_playbook`, 05+) to a
terminology mismatch between spec/design prose ("snapshot") and code (`RoutingContext`). Introduce
a *new* `RoutingSnapshot` type wrapping/deprecating `RoutingContext` — rejected, pure duplication
for zero benefit; nothing outside this phase's own three spec files references the old name yet.

## D2 — `RoutingSnapshot` stays a pure value object; `RoutingSnapshot::Builder` does the DB work

**Decision**: `RoutingSnapshot` itself remains a `Data.define`-style value object with a
keyword-only custom `initialize` (same pattern as `Playbook`) — zero I/O, constructible directly in
memory (FR-003). All DB querying (conversation → contact/inbox/scout, opportunity lookup, pending
required fields, persisted routing-state lookup) lives in a new
`Custom::ScoutV2::RoutingSnapshot::Builder` service, mirroring the `Playbook` (value) /
`Playbook::Loader` (I/O) split brief 01 already established.

**Rationale**: FR-003 ("constructible directly in memory with fixed values ... no database
connection and no language model call") is only satisfiable if the snapshot type itself has no
query logic baked in. FR-001 ("the system MUST assemble one routing snapshot per turn") still needs
somewhere to live — a separate builder satisfies both without compromise, and is the same shape
brief 01 already validated works for this module (`Loader` builds `Playbook`s from files;
`Builder` builds a `RoutingSnapshot` from a conversation).

**Alternatives considered**: A `RoutingSnapshot.build(conversation)` class method on the value type
itself — rejected; would make "constructible directly in memory with fixed values" (US1's own
Independent Test) require stubbing/bypassing that same method, which is exactly the kind of
DB-coupled construction FR-003 exists to rule out.

## D3 — `opportunity_stage_role` computed privately inside the Builder, no new public method on `Scout`/`Opportunity`

**Decision**: The Builder computes the derived stage role (`:initial`, `:qualified`,
`:unqualified`, or `:none`) as a small private helper, comparing `opportunity.pipeline_stage_id`
against `scout.default_pipeline_stage_id`/`qualified_stage_id`/`unqualified_stage_id` — the exact
three-way comparison `SystemPrompts::FunnelSectionBuilder#stage_role_label`
(`custom/app/services/custom/scout/system_prompts/funnel_section_builder.rb:63-70`) already makes
for prompt display, reused as the single source of truth for what those three columns mean. No new
public method is added to `Scout` or `Opportunity`.

**Rationale**: Spec Assumptions: "this feature exposes that categorization as a reusable value on
the routing snapshot rather than introducing a new source of truth for it" — the source of truth
being reused is the *three-column comparison itself* (already defined once, in
`FunnelSectionBuilder`), not a requirement that a new cross-model public method must exist.
`RoutingSnapshot::Builder` is currently the only caller; adding a public
`Scout#stage_role_for`/`Opportunity#stage_role` method today for a single internal caller would be
exactly the "one-use helper... unless it hides real complexity" the fork's `AGENTS.md` warns
against exposing preemptively (Constitution II). If a later brief's predicate needs the same value,
it reads `RoutingSnapshot#opportunity_stage_role` directly — the field, not a new method, is the
reusable value the spec asks for.

**Alternatives considered**: Add `Scout#stage_role_for(pipeline_stage_id)` — rejected as premature
public-API growth for a single caller (Constitution II); can be promoted later if/when a second
caller (e.g. brief 04+'s `OpportunityInStage` predicate design.md sketches) actually needs it.
Refactor `FunnelSectionBuilder` to share the new helper — rejected, out of scope (no FR touches
prompt building) and would risk an unrelated behavior change to v1's live prompt output.

## D4 — `pending_fields` computed privately inside the Builder from two existing associations

**Decision**: The Builder computes pending required field keys as: the union of
`scout.required_custom_attribute_definitions` (global, `ScoutRequiredField`) and
`opportunity.pipeline_stage.required_custom_attribute_definitions` (stage-specific,
`PipelineStageRequiredField`), filtered to definitions whose `attribute_key` is blank in
`opportunity.custom_attributes`, mapped to `attribute_key`. Private to the Builder — no new public
method on `Opportunity`/`Scout`.

**Rationale**: No existing method already computes "pending fields for the opportunity's *current*
state" — `Opportunity#missing_required_fields`/`Custom::Concerns::OpportunityValidations` populate
this only as a *save-time validation error* (`attr_accessor`, set inside a `before_save`/validation
callback), not a queryable-anytime value, and
`Custom::Scout::OpportunityStageTransitionService#check_global_qualification_requirements` only
checks the *global* (scout-level) required set, never the stage-specific one, and is itself
private to that unrelated service. Building the real thing once, privately, in the one place that
needs it now avoids both misusing a validation-only side channel and growing another model's public
surface for a single caller (Constitution II, same reasoning as D3).

**Alternatives considered**: Reuse `Opportunity#missing_required_fields` — rejected, it is `nil`
until a save has failed; reading it outside that lifecycle would silently return stale/absent data,
not "currently pending," which FR-001 requires.

## D5 — `active_playbook` on the snapshot is the resolved `Playbook` object, not a bare name

**Decision**: `RoutingSnapshot#active_playbook` holds the actual `Custom::ScoutV2::Playbook`
instance (resolved by the Builder via `catalog.find_by_name(state&.active_playbook)`), or `nil` —
never a raw string. The *persisted* `ScoutConversationState#active_playbook` column, by contrast,
stores the plain playbook-name string (playbooks are files, not DB rows — there is nothing to
foreign-key to).

**Rationale**: FR-009's interruption rule needs to compare the active playbook's `priority` against
the winning candidate's `priority` (`winner.priority > active.priority`, strictly). Giving `Router`
the resolved object lets its decision rule be a single direct comparison against data already on
the snapshot, with no second catalog lookup inside `Router` itself — keeping `Router.call` a pure
function of exactly its two arguments (`ctx`, `catalog`) without `ctx` and `catalog` needing to be
cross-referenced twice for the same fact. A playbook name whose file has since been removed/renamed
resolves to `nil` via `Catalog#find_by_name`'s existing nil-safe behavior — treated identically to
"no active playbook" (no special-casing needed; not a scenario spec.md's Edge Cases raises).

**Alternatives considered**: Store/expose only the name and have `Router` re-resolve it via the
`catalog` argument it already receives — rejected, needlessly duplicates the same lookup `Builder`
already had to do to decide the snapshot's own `opportunity`/`contact`/etc. shape, for no
behavioral difference.

## D6 — Turn-scoped transition count is supplied externally, never derived from persisted state

**Decision**: Both `RoutingSnapshot::Builder.call(...)` and
`ScoutConversationState#record_transition!(...)` take the current turn-scoped transition count as
a plain argument from their caller (default `0` for `Builder`, required keyword for
`record_transition!`). Neither reads it from `ScoutConversationState#transition_count` (the
persisted *cumulative* count).

**Rationale**: FR-021 is explicit and load-bearing: the cumulative count "MUST NOT" be treated as
the turn-scoped limit's input. Brief §4 decision 4 states the concrete failure mode this avoids: a
Sidekiq retry reading the cumulative count would inherit a failed attempt's near-limit state and
kill routing on the very next try. Because "a turn attempt" itself is explicitly out of this
phase's scope (spec Assumptions, last bullet — owned by whichever later phase executes a turn),
this phase cannot and does not try to track that count durably; it only defines the counting
*rule* (reset-per-attempt, cap at two, refuse a third, record the refusal) as a function of a
count its future caller supplies.

**Alternatives considered**: Add a `current_turn_id`/similar column so the model can distinguish
"this attempt" from "a prior attempt" itself — rejected, that *is* turn-orchestration state, and
inventing it here would be building brief 03's `TurnRunner` prematurely (Constitution II) for a
requirement (FR-016) that only asks for a reset-to-zero *rule*, not a durable attempt identity.

## D7 — `Router` is a single pure expression; `Decision` is a small nested value object

**Decision**: `Router.call(ctx, catalog)` finds the winner via
`catalog.ordered_by_priority.find { |pb| pb.when_state.present? && Predicates::Evaluator.call(pb.when_state, ctx) }`
(reusing brief 01's `Evaluator`/`Catalog#ordered_by_priority` unchanged), then resolves the
selected playbook with one branching expression covering all six US2 outcomes, and returns
`Router::Decision.new(playbook:, confidence:)` — `1.0` when a playbook is selected, `nil` when
none is (mirrors `Validator::ValidationError` nested-inside-its-owner precedent; no separate file).

**Rationale**: `catalog.ordered_by_priority` (brief 01, already descending) plus `Enumerable#find`
gives "the highest-priority match" for free with no separate max-by/tie-break step — correct
because priority uniqueness is already a boot-time invariant (brief 01's `Validator`), matching
FR-006's own text ("this selection never needs its own tie-break"). The six acceptance scenarios
collapse to one expression:

```ruby
winner.nil?                              then active                 # FR-011/FR-012 (nil if no active either)
active.nil? || winner.name == active.name then winner                 # FR-008/FR-007
winner.priority > active.priority         then winner                 # FR-009 interruption
else                                       then active                 # FR-010
```

satisfying FR-013 for free (a `when_state`-less playbook never enters the `find` candidate set at
all, regardless of priority). `confidence` follows design.md §4.4's own vocabulary directly ("hoje
tem duas implementações... `when_state` (confiança 1.0)").

**Alternatives considered**: A four/five-branch `case` with named intermediate booleans — rejected,
the single expression above is not less readable and avoids inventing intermediate state
(Constitution II, "three similar lines beat a premature abstraction" cuts the other way here: one
expression beats four named booleans that exist only to be read once).

## D8 — `ScoutConversationState` persistence methods: three intention-revealing writers, no generic "apply activation" method

**Decision**: Three instance methods, each mapping directly to one FR-014-family requirement:

- `record_state_activation!(playbook_name)` — sets `active_playbook`, `activated_at = Time.current`,
  `activation_reason = :state`; never touches `last_exit` (FR-014, used for both a fresh activation
  and a priority interruption — both are reason `:state` per this spec's clarification #1).
- `record_transition!(target_playbook_name, turn_transition_count:)` — if
  `turn_transition_count >= 2`, sets only `handoff_limit_reached_at = Time.current` and returns
  `false` (refused, FR-017/FR-018); otherwise sets `active_playbook`/`activated_at`/
  `activation_reason = :transition`, increments the persisted cumulative `transition_count` by one
  (FR-021), and returns `true`. Never touches `last_exit` (FR-020).
- `record_terminal_exit!(exit_name)` — clears `active_playbook`/`activated_at`/`activation_reason`
  to `nil` and sets `last_exit = exit_name`, replacing whatever was there (FR-019). Reactivating a
  playbook later (by either of the other two methods) never reads or clears `last_exit` — it is
  only ever written here (FR-020, clarification #3).

**Rationale**: Each method's name is the exact vocabulary spec.md's Key Entities section already
uses ("state-based activation," "transition hand-off," "terminal ending") — a single generic
`apply!(kind, ...)` method would force every call site to know which kind maps to which field
effects anyway, with no reuse benefit (each kind's field-mutation set genuinely differs: state never
increments a counter or touches `last_exit`; transition increments a counter and never touches
`last_exit`; terminal clears three fields and only ever writes `last_exit`). Returning `true`/`false`
from `record_transition!` is the minimum signal FR-017's "refuse it rather than performing it" needs
for a caller to know whether to end the turn — no richer result type is asked for by any acceptance
scenario.

**Alternatives considered**: A single `record_activation!(playbook_name, reason:)` for both state
and transition, with the cap-check as a separate step — rejected: the cap-check and the
counter-increment are transition-only behavior (FR-016/FR-017/FR-021 never apply to `:state`), so
splitting them out is what keeps `record_state_activation!` simple rather than passing a `reason:`
whose `:transition` case implies extra required arguments (`turn_transition_count:`) the `:state`
case must never accept.

## D9 — `ScoutConversationState.for_conversation(conversation)`: find-or-initialize, never forces a write on read

**Decision**: A class method `for_conversation(conversation)` doing
`find_or_initialize_by(conversation_id: conversation.id) { |s| s.account_id = conversation.account_id }`
— returns a persisted record if one exists, or a new, unsaved, all-defaults instance otherwise.
Used by `RoutingSnapshot::Builder` to read `active_playbook`/etc. without forcing a row to exist
just because a turn was routed.

**Rationale**: Spec Edge Cases: "A conversation has no persisted routing state yet (its very first
turn) — treated exactly like 'no playbook is currently active.'" A brand-new
`ScoutConversationState.new` already defaults `active_playbook`/`activation_reason`/`last_exit` to
`nil` and `transition_count` to `0` (column defaults), so reading from an unsaved instance produces
exactly that "no active playbook" shape with zero special-casing in the Builder, and with no
side-effecting `INSERT` on a code path that is conceptually a read.

**Alternatives considered**: `find_or_create_by!` — rejected; would perform a write (and risk a
unique-index race under concurrent first-turns for the same conversation) purely to satisfy a read,
and nothing in this phase requires the row to exist before the first actual `record_*!` call.

## D10 — New model/table naming: flat `ScoutConversationState` / `ichatr_scout_conversation_states`

**Decision**: `custom/app/models/scout_conversation_state.rb` defining a flat, unnamespaced
`ScoutConversationState < ApplicationRecord` with `self.table_name = 'ichatr_scout_conversation_states'`
— the exact table name design.md §4.4 already commits to.

**Rationale**: Verified two distinct, non-overlapping conventions already in the fork's
`custom/app/models/` tree: (a) flat files directly under `custom/app/models/*.rb` define new,
fork-owned, *unnamespaced* AR models (`Scout`, `Opportunity`, `PipelineStage`, `ScoutTool`,
`ScoutInbox`, ...); (b) `custom/app/models/custom/*.rb` defines `Custom::*`-namespaced *extension
modules* mixed into existing **upstream** models via `include_mod_with`/`prepend_mod_with`
(confirmed: `app/models/conversation.rb:434-437` wires `Custom::Conversation` from
`custom/app/models/custom/conversation.rb` this exact way). `ScoutConversationState` is a brand-new
fork-owned entity with no upstream model to extend, so convention (a) applies — matching
`Custom::ScoutV2::*` namespacing here (as `custom/app/services/custom/scout_v2/*` does) would
incorrectly imply this model participates in mechanism (b), which it does not.

**Alternatives considered**: `Custom::ScoutV2::ConversationState` under
`custom/app/models/custom/scout_v2/conversation_state.rb` — rejected as a category error per the
above; would also require a *second*, unrelated-to-extension `custom/` subdirectory nesting inside
`custom/app/models/custom/` purely to fabricate the desired namespace, diverging from both
established meanings that directory already carries in this repo.

## D11 — Migration: additive-only new table, `account_id` present for query-scoping parity with sibling tables

**Decision**: One new migration, timestamp `21260924000000` (next after the latest existing
`ichatr_*` migration, `21260911140000`), creating `ichatr_scout_conversation_states` with
`account_id` (bigint, FK to `accounts`, `on_delete: :cascade`), `conversation_id` (bigint, FK to
`conversations`, `on_delete: :cascade`, unique index — one row per conversation), `active_playbook`
(string), `activated_at` (datetime), `activation_reason` (integer, nullable — Rails `enum state: 0,
trigger: 1, transition: 2`, all three values present from day one though only `state` is produced
by this phase's code), `transition_count` (integer, `default: 0, null: false`),
`handoff_limit_reached_at` (datetime), `last_exit` (string), `unsatisfied_flags` (jsonb, `default:
{}, null: false` — reserved, unpopulated this phase per spec Assumptions), timestamps.

**Rationale**: Every existing `ichatr_*` table carries `account_id` even when a more specific FK
already scopes it (e.g. `ichatr_opportunity_conversations`, `ichatr_campaign_recipients`) — kept
for query-scoping/index parity with the rest of the fork's schema, not a new pattern. `activation_reason`
ships with all three enum values now (rather than adding `trigger` in a later migration) because
spec.md's own Key Entities section already fixes the three-value vocabulary — adding the unused
value costs nothing and avoids a schema-only migration purely to add an enum member later.
`unsatisfied_flags` defaults to `{}` and is otherwise untouched by this phase's code, matching spec
Assumptions verbatim ("this feature creates that field but does not populate or read it").

**Alternatives considered**: Omit `account_id`, join through `conversation.account_id` when
needed — rejected, breaks the fork's own established indexing convention for every sibling
`ichatr_*` table for no isolation benefit (Constitution III, adhere to established conventions).
