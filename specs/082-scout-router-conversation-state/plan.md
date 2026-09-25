# Implementation Plan: Scout Deterministic Router and Conversation Routing State

**Branch**: `082-scout-router-conversation-state` | **Date**: 2026-09-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/082-scout-router-conversation-state/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command; its definition describes the execution workflow.

## Summary

Replace `AgentRunner`'s unconditional prompt/tool assembly with a deterministic, state-only
router: a `RoutingSnapshot` assembled once per turn from real conversation/contact/inbox/scout/
opportunity state (never re-queried mid-decision), a pure `Router.call(ctx, catalog)` that picks
the highest-priority matching playbook using only `when_state` predicates from brief 01 (never an
LLM), and a new per-conversation `ScoutConversationState` table that durably records every
activation (`state`/`trigger`/`transition`), a playbook's own declared transition hand-offs
(capped at 2 per turn attempt, refusal recorded with a dedicated marker) and terminal exits (last
exit). This is the epic's stated cut-line: proven entirely by specs with zero LLM/network calls.
Turn orchestration, prompt assembly, and the trigger/intent half of activation are explicitly out
of scope (briefs 03/04).

## Technical Context

**Language/Version**: Ruby 3.4.4 (existing Rails 7 app; no new language/runtime).

**Primary Dependencies**: None new. Reuses brief 01's `Custom::ScoutV2::Playbook::Catalog`,
`Predicates::Evaluator`/`Registry` exactly as delivered — no new predicate, no new frontmatter
field, no new gem. Standard ActiveRecord for the new table.

**Storage**: One new table, `ichatr_scout_conversation_states` (additive migration only —
Constitution I's migration exception; no existing table is altered). Playbooks themselves remain
files, not DB rows (unchanged from brief 01) — the new table stores only *behavioral state per
conversation* (which playbook name is active, when/why, transition/exit history), never playbook
definitions.

**Testing**: RSpec under `custom/spec/services/custom/scout_v2/**` (router, routing snapshot,
builder — no DB required for `Router`/`RoutingSnapshot` per US1/US2, real DB + factories for
`RoutingSnapshot::Builder`) and `custom/spec/models/scout_conversation_state_spec.rb` (US3, real
persisted records — Constitution Principle VII forbids mocking the AR model under test). Run
inside the `rails` container: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test
bundle exec rspec <path>` (`AGENTS.md`).

**Target Platform**: Same Rails app server / Sidekiq / `rails console` / RSpec boot. No new boot
wiring — this phase adds a queryable model + two pure services, not another `after_initialize`
validator (brief 01 already gates playbook-file correctness at boot).

**Performance Goals**: `Router.call` and `RoutingSnapshot.new` do zero I/O — pure in-memory
decision over an already-loaded catalog and an already-built snapshot (FR-002/FR-003, SC-001).
`RoutingSnapshot::Builder` does a small, fixed number of indexed lookups per turn (conversation →
contact/inbox/scout via existing associations, one `ScoutConversationState` row by unique
`conversation_id`, one opportunity via `active_conversation` association) — no N+1, no LLM call
(SC-001).

**Constraints**: Router never queries the database or calls an LLM mid-decision (FR-002); the
turn-scoped transition-hand-off count is never read from the persisted cumulative count (FR-016,
FR-021 — they are deliberately different numbers so a Sidekiq retry can't inherit a failed
attempt's near-limit state, brief §4 decision 4); RuboCop 150-char lines and complexity cops
resolved by extraction, never `.rubocop_todo.yml`/`Max` overrides (`AGENTS.md`).

**Scale/Scope**: Exactly brief §5's preliminary scope — `Router`, the now-full `RoutingSnapshot`
(renamed from brief 01's two-field seed, see research.md D1), its DB-querying `Builder`, and the
`ScoutConversationState` model + migration. No turn orchestration (`TurnRunner`, brief 03), no
trigger-based activation (`open_playbook`, brief 04), no capability resolution (brief 07 —
`satisfied_capabilities` is a pass-through field this phase, never computed/exercised here).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First** — PASS. Every new/changed file lives under `custom/`
  (`custom/app/services/custom/scout_v2/**`, `custom/app/models/scout_conversation_state.rb`,
  `custom/spec/**`) plus one new migration under `db/migrate/` (the constitution's explicit
  infrastructure exception — additive only, creates a brand-new table, alters nothing existing).
  No upstream/Enterprise file is touched. `AgentRunner`/`SystemPromptsService` remain untouched
  (brief §6 "Fora de escopo": prompt assembly and turn execution are brief 03) — this phase builds
  the router and its persistence, not the wiring that calls it in production yet.
- **II. Smallest Production-Ready Change** — PASS. Scope is exactly brief §5's preliminary scope.
  No speculative `CapabilityRegistry` resolution (brief 07), no trigger/intent classifier (brief
  04, explicitly deferred by design.md §4.4's own "não entra no primeiro corte"), no turn-retry
  orchestration (that's `TurnRunner`, brief 03 — this phase's `record_transition!` takes the
  turn-scoped count as a plain argument rather than inventing a turn-tracking mechanism it isn't
  scoped to own). `opportunity_stage_role`/`pending_fields` computation stays private to
  `RoutingSnapshot::Builder` rather than growing `Opportunity`/`Scout`'s public API for a value
  only this one caller needs today (research.md D3/D4).
- **III. Adhere to Established Conventions** — PASS (verified at implementation time via
  `rubocop`/`eslint`). Follows brief 01's own `Custom::ScoutV2::*` namespacing, `Data.define`
  value-object style (`Playbook`), and nested-nowhere-else-needed value types (`Validator::
  ValidationError` precedent → `Router::Decision`). The new AR model follows the fork's existing
  flat, unnamespaced model convention (`Scout`, `Opportunity`, `PipelineStage`, `ScoutTool`,
  `ScoutInbox`) — `custom/app/models/custom/**` is reserved for upstream-model extension modules
  (`Custom::Conversation` mixed into core `Conversation` via `include_mod_with`), a different
  mechanism this new table has no relationship to (verified: `app/models/conversation.rb:434-437`
  wires exactly that mechanism; the new table is a wholly fork-original entity, not an extension
  of an upstream model).
- **IV. Safe, Reversible Change Management** — PASS. Additive migration (new table only,
  reversible via standard `down`), additive/renamed fork-only files, no destructive operations.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — PASS, decision recorded (same as brief 01):
  ScoutV2 is a fork-original module with no upstream or Enterprise equivalent; Enterprise's own
  `Captain::Scenario` is a structurally different, DB-row/UI-authored system (design.md §2.4). No
  `prepend_mod_with`/`include_mod_with` extension point applies — nothing upstream is being
  extended.
- **VI–VIII. TDD / Observable Behavior / Functional Slices** — Plan commits to spec-first delivery
  per brief §8 and this spec's Independent Tests: `router_spec.rb` (a table of playbook-set +
  snapshot-state → expected-winner cases, no DB, no LLM, covering continuity/interruption/
  non-strict-winner/nothing-matches/trigger-only-never-wins), `routing_snapshot_spec.rb`
  (in-memory construction, every field reads back exactly as given, no DB), `routing_snapshot/
  builder_spec.rb` (real `Conversation`/`Contact`/`Inbox`/`Scout`/`Opportunity`/
  `ScoutConversationState` records via factories — no mocking of these internal collaborators
  per Principle VII), `scout_conversation_state_spec.rb` (real persisted records: state
  activation/interruption, transition hand-off up to and past the 2-per-turn cap with the
  limit-reached marker, terminal exit clearing/recording `last_exit`, a reactivated playbook
  leaving a prior `last_exit` untouched, a fresh turn-scoped count starting at zero independent of
  the persisted cumulative count — directly exercising every US3 acceptance scenario). All
  fixtures are real DB records/factories or in-memory value objects; no mocking of the router,
  snapshot, builder, or model under test. No `type: :request`/Vitest entry-point test exists this
  phase because none is reachable yet — turn execution/controller wiring is brief 03's scope; until
  then, `Router.call`/`RoutingSnapshot.new`/`ScoutConversationState`'s public methods (all exercised
  directly above) are the real entry points this phase exposes, satisfying Principle VI's third
  bullet at the boundary this phase actually owns.
- **IX. Surgical Execution Scope** — Plan commits to running only the targeted spec files during
  implementation; full suite reserved for pre-integration/release gates.

No violations. Complexity Tracking is not needed.

**Post-Phase 1 re-check**: data-model.md/contracts/quickstart.md introduce exactly one new table
(no alteration of any existing table), no new files outside `custom/` + the one migration, no
mocking of internal collaborators in the planned specs, and no new gem — all gates above still
PASS unchanged. The `RoutingContext` → `RoutingSnapshot` rename (research.md D1) is a same-phase
cutover of the exact entity this feature extends (three brief-01 spec files + the one source
file), not a drive-by rename of unrelated code.

## Project Structure

### Documentation (this feature)

```text
specs/082-scout-router-conversation-state/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   └── ruby-interfaces.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

**Structure Decision**: Single Rails monolith (existing app). New/changed feature code stays
isolated under the fork's `custom/` overlay tree (Constitution I), extending brief 01's
`Custom::ScoutV2::*` namespace in place plus one new flat, unnamespaced AR model (matching the
fork's existing `Scout`/`Opportunity`/`PipelineStage` model convention) and its additive
migration.

```text
custom/
├── app/
│   ├── services/custom/scout_v2/
│   │   ├── playbook.rb                          # UNCHANGED (brief 01)
│   │   ├── playbook/**                           # UNCHANGED (brief 01)
│   │   ├── predicates/**                         # UNCHANGED (brief 01) — reused as-is by Router
│   │   ├── capabilities/catalog.rb               # UNCHANGED (brief 01)
│   │   ├── routing_context.rb                    # REMOVED — renamed to routing_snapshot.rb
│   │   ├── routing_snapshot.rb                   # NEW (renamed+expanded) — Custom::ScoutV2::RoutingSnapshot
│   │   ├── routing_snapshot/
│   │   │   └── builder.rb                        # NEW — ::RoutingSnapshot::Builder (DB-querying assembler)
│   │   └── router.rb                             # NEW — Custom::ScoutV2::Router (+ nested ::Decision)
│   └── models/
│       └── scout_conversation_state.rb           # NEW — ScoutConversationState (flat, unnamespaced AR model)
└── spec/
    ├── services/custom/scout_v2/
    │   ├── predicates/
    │   │   ├── evaluator_spec.rb                  # UPDATED — RoutingContext -> RoutingSnapshot refs
    │   │   ├── opportunity_open_spec.rb            # UPDATED — same
    │   │   └── pending_required_fields_spec.rb     # UPDATED — same
    │   ├── routing_snapshot_spec.rb                # NEW — in-memory construction (US1)
    │   ├── routing_snapshot/
    │   │   └── builder_spec.rb                     # NEW — real-DB assembly (US1)
    │   └── router_spec.rb                          # NEW — decision table, no DB/LLM (US2)
    └── models/
        └── scout_conversation_state_spec.rb        # NEW — persistence behavior (US3)

db/migrate/
└── 21260924000000_create_ichatr_scout_conversation_states.rb   # NEW — additive-only table
```
