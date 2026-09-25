# Implementation Plan: Scout V2 Turn Runner and Qualification Playbook (Playground)

**Branch**: `083-scout-turn-runner-playground` | **Date**: 2026-09-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/083-scout-turn-runner-playground/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command; its definition describes the execution workflow.

## Summary

Introduce `Custom::ScoutV2::TurnRunner`: the first live execution path that wires brief 01's
playbook catalog and brief 02's router + `ScoutConversationState` into a real turn — one
`scout.llm_chat` call, prompt assembled fresh from whichever playbook the router selects (or a
minimal fallback), a tool catalog built from exactly that playbook's declared tools plus the
always-on read-only knowledge lookup, and the resulting routing decision persisted before the
reply is dispatched. Ship the epic's first playbook, `qualificacao` (state-activated, zero
capabilities, one tool). Gate both the inbox job and the playground endpoint behind a new
account-level `scout_v2` flag so v1 (`AgentRunner`/`ResponseAuditor`/`SystemPromptsService`) stays
completely undiffed and production accounts see zero behavioral change until promoted (a later
phase). The one genuinely new mechanism this phase must design (not named explicitly in brief 03's
scope list, but required by its own acceptance criteria): the playground surface, today fully
ephemeral with no backing database conversation, gains a lazily-created, per-scout, real sandbox
`Conversation` — the only way `ScoutConversationState` and a real `Opportunity` can be exercised
from the playground at all (research.md D1–D3).

## Technical Context

**Language/Version**: Ruby 3.4.4 (existing Rails 7 app; no new language/runtime).

**Primary Dependencies**: None new. Reuses brief 01's `Custom::ScoutV2::Playbook::{Loader,Catalog,Validator}`
and brief 02's `Custom::ScoutV2::{Router,RoutingSnapshot,RoutingSnapshot::Builder}` +
`ScoutConversationState` exactly as delivered (no signature change to any of them). Reuses v1's
`Custom::Scout::Tools::{SearchKnowledgeBase,ManageOpportunity}` and
`Integrations::LlmInstrumentation` unchanged. RubyLLM `1.15.0` (already a dependency, `Scout#llm_chat`).

**Storage**: No new migration, no new table, no new column (research.md D2). The playground
sandbox conversation (research.md D1) is resolved via existing tables only (`contacts`, `inboxes`,
`ichatr_scout_inboxes`, `contact_inboxes`, `conversations`), keyed off `Contact#identifier`
(existing, already unique-per-account). `ichatr_scout_conversation_states` (brief 02) gains rows
for both surfaces via its existing, unchanged `record_state_activation!`.

**Testing**: RSpec under `custom/spec/services/custom/scout_v2/turn_runner_spec.rb` (prompt/tool
catalog composition + persisted state, LLM client doubled per brief 03 §8 — Independent Test
explicitly allows this) and `custom/spec/services/custom/scout_v2/playground_conversation_spec.rb`
(real DB, idempotent find-or-create). `custom/spec/services/custom/scout_v2/playbook/loader_spec.rb`-style
fixture-file coverage is not needed (no loader change) but `custom/playbooks/qualificacao.md` gets
exercised implicitly by every `Playbook::Loader`/`Validator` spec that walks the real directory —
confirm those still pass with the new file present. `custom/spec/jobs/custom/scout/process_message_job_spec.rb`
and a new `custom/spec/requests/api/v1/accounts/scouts/playground_messages_controller_spec.rb`
(or extend the existing controller spec if one exists) cover the flag-gated dispatch branch itself
(`type: :request`/job spec — Constitution VI's real-entry-point requirement). Run inside the
`rails` container: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec <path>` (`AGENTS.md`).

**Target Platform**: Same Rails app server / Sidekiq / RSpec boot. `custom/playbooks/qualificacao.md`
is picked up by brief 01's existing boot-time validation — no new initializer/task.

**Performance Goals**: Exactly one top-level LLM call per turn attempt (SC-001) — a strict
reduction from v1's 3–8. `PlaygroundConversation.for` does a small, fixed number of indexed
lookups (`Contact#identifier` unique index, `ContactInbox`/`Conversation` FK lookups), first-call
only pays the one-time Inbox/Contact/ContactInbox/Conversation creation cost; every subsequent
playground call for the same scout is a single indexed read.

**Constraints**: `TurnRunner` never creates a real `Message` row for the playground surface
(research.md D3 — the specific, verified mechanism that prevents `Custom::ScoutListener`
double-enqueuing `ProcessMessageJob` on the sandbox conversation). `AgentRunner`, `ResponseAuditor`,
`SystemPromptsService`, and every file under `custom/app/services/custom/scout/tools/**` receive
zero diff (brief 03 §6, research.md D8). RuboCop 150-char lines and complexity cops resolved by
extraction, never `.rubocop_todo.yml`/`Max` overrides (`AGENTS.md`).

**Scale/Scope**: Exactly brief §5's preliminary scope plus the one mechanism it requires but
doesn't name (research.md D1–D3): `Custom::ScoutV2::TurnRunner`, `Custom::ScoutV2::PlaygroundConversation`,
`custom/playbooks/qualificacao.md`, the `scout_v2` flag + MANIFEST entry, and the two named
dispatch-point branches. No `open_playbook`/playbook index/typed Instructions (brief 04), no exits/
Escalation/auditor removal — there is no auditor to remove in v2, it was simply never built (brief
05), no additional playbooks (brief 06), no `CapabilityRegistry` (brief 07).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First** — PASS. All new Ruby code lives under `custom/`
  (`custom/app/services/custom/scout_v2/{turn_runner.rb,playground_conversation.rb}`,
  `custom/playbooks/qualificacao.md`, `custom/spec/**`). The only touched files outside `custom/`
  are `config/features.yml` (additive entry, MANIFEST-covered — the constitution's own precedent
  for `scout`/`erp_integration`, research.md D12) and `bin/sync-custom-module-hooks` itself (the
  MANIFEST mechanism, not a behavior file). `custom/app/jobs/custom/scout/process_message_job.rb`
  and `custom/app/controllers/api/v1/accounts/scouts/playground_messages_controller.rb` are
  fork-owned files (not upstream/Enterprise) gaining one conditional branch each — brief 03 §5's
  explicit, named scope. No migration.
- **II. Smallest Production-Ready Change** — PASS. `PlaygroundConversation` (research.md D2) reuses
  four existing, already-established construction patterns (seeders, prior specs' quickstart.md)
  instead of inventing schema; `TurnRunner`'s tool-name map (research.md D7) is the minimum needed
  for today's one playbook, not a speculative registry; no `.with_schema`/`ResponseSchema` reuse
  where nothing consumes the split (research.md D9); no reset-playground mechanism, no per-user
  sandbox isolation — both explicitly named as accepted, undesigned-for consequences (research.md
  D2) rather than speculative scope.
- **III. Adhere to Established Conventions** — PASS (verified at implementation time via
  `rubocop`/`rspec`). Follows brief 01/02's `Custom::ScoutV2::*` namespacing and the fork's
  existing `Channel::Api`+`Inbox`+`ContactInbox`+`Conversation` synthetic-record convention
  verified in four other places in the repo (research.md D2).
- **IV. Safe, Reversible Change Management** — PASS. No migration to reverse. Feature flag defaults
  `enabled: false`; toggling it back off restores v1 behavior on the very next message with no
  deploy (FR-005, verified as the exact same mechanism `captain_integration_v2` already uses).
- **V. Dual-Tree Awareness (OSS + Enterprise)** — PASS, decision recorded (same as briefs 01/02):
  ScoutV2 is a fork-original module with no upstream/Enterprise equivalent; `captain_integration_v2`
  is confirmed precedent for the flag-selects-engine pattern itself (design.md §4.11), not a file
  this feature extends or conflicts with.
- **VI–VIII. TDD / Observable Behavior / Functional Slices** — Plan commits to spec-first delivery
  per brief §8 and this spec's Independent Tests: `turn_runner_spec.rb` (prompt/tool-catalog
  composition + persisted `ScoutConversationState`, LLM client doubled — brief 03 §8/spec US1
  Independent Test explicitly sanctions this as the correct boundary, no real model call needed),
  `playground_conversation_spec.rb` (real DB records, idempotent resolution — no mocking of AR
  models per Principle VII), dispatch-branch specs for both `ProcessMessageJob` and
  `PlaygroundMessagesController` (real entry points — job spec + `type: :request` spec, satisfying
  Principle VI's third bullet). No test asserts on prompt/reply *wording* (cosmetic) — assertions
  target assembled instructions *containing* the playbook body/pending-fields data, exact tool
  list, and persisted state row, matching Principle VII's "observable state" bar.
- **IX. Surgical Execution Scope** — Plan commits to running only the targeted spec files during
  implementation; full suite reserved for pre-integration/release gates.

No violations. Complexity Tracking is not needed.

**Post-Phase 1 re-check**: data-model.md/contracts/quickstart.md introduce no new table, no diff
to any of the four explicitly-undiffed v1 files (`AgentRunner`, `ResponseAuditor`,
`SystemPromptsService`, `custom/app/services/custom/scout/tools/**`), no mocking of internal AR
collaborators in the planned specs, and no new gem — all gates above still PASS unchanged. The
`PlaygroundConversation` mechanism (research.md D1–D3), while not named in brief 03 §5's literal
file list, is the smallest change that makes the brief's own named US1/US3 acceptance criteria
achievable at all — documented in full in research.md rather than silently assumed.

## Project Structure

### Documentation (this feature)

```text
specs/083-scout-turn-runner-playground/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md         # Phase 1 output (/speckit.plan command)
├── quickstart.md         # Phase 1 output (/speckit.plan command)
├── contracts/            # Phase 1 output (/speckit.plan command)
│   └── ruby-interfaces.md
└── tasks.md              # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

**Structure Decision**: Single Rails monolith (existing app). New feature code stays isolated
under the fork's `custom/` overlay tree (Constitution I), extending briefs 01/02's
`Custom::ScoutV2::*` namespace in place, plus one new playbook file and the two named dispatch-point
edits.

```text
custom/
├── app/
│   ├── services/custom/scout_v2/
│   │   ├── playbook.rb, playbook/**, predicates/**, capabilities/catalog.rb   # UNCHANGED (brief 01)
│   │   ├── router.rb, routing_snapshot.rb, routing_snapshot/builder.rb        # UNCHANGED (brief 02)
│   │   ├── turn_runner.rb                        # NEW — Custom::ScoutV2::TurnRunner
│   │   └── playground_conversation.rb            # NEW — Custom::ScoutV2::PlaygroundConversation
│   ├── models/scout_conversation_state.rb        # UNCHANGED (brief 02)
│   ├── jobs/custom/scout/process_message_job.rb  # ONE new conditional branch (scout_v2)
│   └── controllers/api/v1/accounts/scouts/
│       └── playground_messages_controller.rb     # ONE new conditional branch (scout_v2)
├── playbooks/
│   └── qualificacao.md                           # NEW — the epic's first playbook
└── spec/
    ├── services/custom/scout_v2/
    │   ├── turn_runner_spec.rb                    # NEW — prompt/tools/persisted-state (US1/US2)
    │   └── playground_conversation_spec.rb        # NEW — idempotent sandbox resolution
    ├── jobs/custom/scout/process_message_job_spec.rb                  # UPDATED — flag branch
    └── requests/api/v1/accounts/scouts/
        └── playground_messages_controller_spec.rb # UPDATED/NEW — flag branch

config/
└── features.yml                                  # ONE new entry — scout_v2 (research.md D12)

bin/
└── sync-custom-module-hooks                       # ONE new MANIFEST entry (config/features.yml)
```
