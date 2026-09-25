# Implementation Plan: Scout V2 Typed Instructions, Playbook Index, and Mid-Turn Playbook Activation

**Branch**: `084-scout-instructions-open-playbook` | **Date**: 2026-09-25 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/084-scout-instructions-open-playbook/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command; its definition describes the execution workflow.

## Summary

Replace the always-on part of the Scout V2 turn prompt with four typed, config-driven sections
(Identity/Communication/Memory/Safety) instead of prose; add an always-on one-line-per-playbook
index the model can read; and add a model-invoked `open_playbook` tool that, when no playbook is
already forced by conversation state, opens a catalog playbook by name mid-turn — injecting its
body (as the tool's own result), tools, and declared exits/capabilities data into the same
`chat.ask` call, with the activation recorded as `trigger`-based. Builds entirely on the turn
engine, router, and playbook catalog already delivered by Briefs 01–03; touches only the v2
namespace (`custom/app/services/custom/scout_v2/`) plus two new `Scout` columns — v1's
`system_prompts_service.rb` and its execution path are untouched (FR-017).

## Technical Context

**Language/Version**: Ruby 3.4.4 (Rails 7, per `Gemfile`)

**Primary Dependencies**: RubyLLM 1.15.0 (`chat.with_instructions`/`with_tool`, in-place mutation
mid-`ask` — verified in-container, see `research.md` §1), existing `Custom::ScoutV2::*` engine
(`TurnRunner`, `Router`, `RoutingSnapshot`, `Playbook`/`Playbook::Catalog`/`Playbook::Loader`,
`Predicates::*`), existing `Custom::Scout::Tools::{SearchKnowledgeBase,ManageOpportunity}` (reused
as-is), `Integrations::LlmInstrumentation`, `Custom::Scout::Tools::CallRecorder`

**Storage**: PostgreSQL — one additive migration on the existing fork-owned `ichatr_scouts` table
(3 new columns); no new tables. `ichatr_scout_conversation_states` unchanged (its
`activation_reason` enum already has the `trigger` value this feature starts using).

**Testing**: RSpec (`bundle exec rspec`), targeted per Constitution Principle IX — no LLM calls in
specs; `RubyLLM::Chat` doubled with `instance_double` at the one legitimate external boundary
(Principle VII), everything else (Scout, ScoutConversationState, Playbook catalog, Opportunity)
exercised against the real test DB, matching every existing `scout_v2` spec's convention.

**Target Platform**: Rails app server (containerized, rootless Podman per `AGENTS.md`)

**Project Type**: Web application backend module (Rails engine-style namespace inside a monolith;
no frontend surface touched — see `research.md` §8)

**Performance Goals**: No new LLM calls per turn (still exactly 1 top-level `chat.ask`, matching
the existing v2 invariant `design.md` §4.6 measures) — `open_playbook` executes inside the same
`chat.ask`'s tool loop, not as an extra round trip.

**Constraints**: Zero behavior change to the v1 execution path (FR-017); Instructions block must
be exactly 4 sections with no data-driven variability in section *count* (only content); playbook
index block must never be blank even with zero playbooks; `open_playbook` must never raise for an
unknown name.

**Scale/Scope**: One additive migration on 1 table, ~2 new small enums, 4 new instruction-section
builder classes + 1 composer, 1 new index-builder class, 1 new tool class, 1 new shared tool
registry, 1 new model method, and a bounded rewrite of `TurnRunner`'s prompt/tool-assembly private
methods (public interface — `.new(...).perform` — unchanged).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Upstream Compatibility First | PASS | Every new file lives under `custom/`; the only migration is an additive `add_column` × 3 on a table (`ichatr_scouts`) that already only exists in this fork, following the exact pattern of 6 prior migrations on the same table. No upstream/enterprise file touched. |
| II. Smallest Production-Ready Change | PASS | Scope bounded to exactly the 4 touch points the source brief (§5) lists, plus the 3 narrowly-justified adjacent items research.md documents (shared tool registry to avoid duplication, `record_trigger_activation!` mirroring an existing method, `metadata_for`'s activation-reason fix — each a direct, unavoidable consequence of the feature, not speculative addition). No UI, no capability registry, no exit mechanism — all explicitly deferred by the brief itself. |
| III. Adhere to Established Conventions | PASS | New Rails enums mirror `ScoutConversationState#activation_reason`'s exact declaration style already in the tree; new service classes follow the existing `Custom::ScoutV2::*` compact-class, `.call`-class-method convention (`Predicates::Registry`, `RoutingSnapshot::Builder`); prompt/tool text is Portuguese prose with no i18n keys, matching every existing `SystemPromptsService`/playbook-body precedent (LLM-facing text, not UI copy — `design.md` §4.3 confirms playbook bodies are explicitly out of the i18n cycle, and Instructions-block prose sits in the same category). |
| IV. Safe, Reversible Change Management | PASS | Migration is a plain reversible `change` method (`add_column` × 3); no destructive operation anywhere in this feature. |
| V. Dual-Tree Awareness (OSS + Enterprise) | PASS | Confirmed via `grep -rn Scout enterprise/` → zero matches. The Scout module has no Enterprise overlay to keep in sync. |
| VI–VIII. TDD / Observable Behavior / Functional Slices | PASS (commitment carried into `/speckit.tasks`) | Every new class gets a spec exercising real Rails models against the test DB; the one test double is `RubyLLM::Chat` (external LLM boundary), matching `turn_runner_spec.rb`'s existing pattern. `turn_runner_spec.rb`'s "fallback instructions" context is a genuine behavior change (FR-019 removes `FALLBACK_INSTRUCTIONS`) and will be rewritten, not just patched, in the same commit as the behavior change. |
| IX. Surgical Execution Scope | PASS (commitment carried into `/speckit.tasks`) | Quickstart's targeted spec list (not full suite) is the working-session command; full suite reserved for pre-release per existing project convention. |

No violations — Complexity Tracking table below is empty by design.

## Project Structure

### Documentation (this feature)

```text
specs/084-scout-instructions-open-playbook/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md         # Phase 1 output (/speckit.plan command)
├── quickstart.md         # Phase 1 output (/speckit.plan command)
├── contracts/            # Phase 1 output (/speckit.plan command)
│   ├── open_playbook_tool.md
│   └── turn_prompt_blocks.md
└── tasks.md              # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
custom/
├── app/
│   ├── models/
│   │   └── scout_conversation_state.rb          # + record_trigger_activation!
│   └── services/custom/
│       ├── scout.rb                              # existing; Scout model gets tone/response_length/greeting
│       └── scout_v2/
│           ├── turn_runner.rb                    # rewritten private prompt/tool-assembly methods (build_instructions, build_tools)
│           ├── instructions/                     # NEW
│           │   ├── builder.rb                    # composes the 4 sections in order; Memory/Safety are fixed constants here
│           │   ├── identity_builder.rb
│           │   └── communication_builder.rb       # tone/response_length/greeting → fixed sentences
│           ├── playbook/
│           │   ├── index_builder.rb               # NEW — always-on one-line-per-playbook block
│           │   ├── pending_fields_formatter.rb    # NEW — pending-required-fields block, moved out of TurnRunner
│           │   └── validator.rb                   # existing; + boot check that every `tools:` name is in the Registry
│           └── tools/                             # NEW namespace
│               ├── registry.rb                    # NEW — shared playbook-tool-name → instance resolution
│               └── open_playbook.rb                # NEW — the mid-turn activation tool
├── db/  (N/A — Rails migrations are repo-root db/migrate/, additive exception per Constitution I)
└── spec/
    ├── models/scout_conversation_state_spec.rb     # + record_trigger_activation! coverage
    ├── models/scout_spec.rb                        # + tone/response_length enum coverage
    └── services/custom/scout_v2/
        ├── turn_runner_spec.rb                     # rewrite fallback-context test; add open_playbook integration coverage
        ├── instructions/
        │   ├── builder_spec.rb
        │   └── communication_builder_spec.rb
        ├── playbook/
        │   ├── index_builder_spec.rb
        │   └── validator_spec.rb
        └── tools/
            ├── open_playbook_spec.rb
            └── registry_spec.rb

db/migrate/
└── 21260925000000_add_communication_style_to_ichatr_scouts.rb   # NEW, additive only
```

**Structure Decision**: Single Rails monolith; all new production code lives inside the existing
`custom/app/services/custom/scout_v2/` fork-specific tree (mirrors the `enterprise/` overlay
convention per Constitution I), plus one model method and one migration on the fork-owned
`ichatr_scouts`/`ichatr_scout_conversation_states` tables. No new top-level directory, no new
frontend surface (see `research.md` §8 for why the Vue settings UI is explicitly out of scope).

## Complexity Tracking

*No Constitution Check violations — table intentionally empty.*
