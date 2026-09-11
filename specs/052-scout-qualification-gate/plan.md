# Implementation Plan: Scout Funnel Stage Qualification Gate

**Branch**: `052-scout-qualification-gate` | **Date**: 2026-08-27 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/052-scout-qualification-gate/spec.md`

## Summary

The Scout AI SDR agent currently has zero visibility into an account's funnel stages or
qualification requirements, and any stage-move validation failure crashes the conversation into a
generic fail-safe handoff instead of giving the agent something actionable. This feature (1) adds
a `funnel_section` to the Scout system prompt exposing the stage catalog (including each stage's
operator-authored purpose description, when set), per-stage required attributes, and Scout-wide
qualification requirements — each attribute carrying its own semantic description when the
operator has configured one, so the agent understands not just field names/types but what they
mean and why a stage exists; (2) introduces a single enforcement point
(`Custom::Scout::OpportunityStageTransitionService`) used by both `move_opportunity_stage` and
`manage_opportunity` so neither tool can bypass the qualification gate or the existing
per-stage-required-field model validation; (3) extracts the existing handoff logic out of the
`handover_to_human` tool into a reusable `Custom::Scout::HandoffService` so it can also fire
automatically, exactly once, when an opportunity actually transitions into the qualified stage; and
(4) removes the `lost_reason`/auto-`status: lost` behavior from `move_opportunity_stage`, since the
Scout must never close an opportunity — disqualification only moves the stage, leaving `won`/`lost`
as an exclusively human action via the existing Kanban UI. No database schema changes, no new
models, and no frontend changes are required — every entity involved (`Scout`, `PipelineStage`,
`PipelineStageRequiredField`, `ScoutRequiredField`, `Opportunity`) already exists with the needed
data.

## Technical Context

**Language/Version**: Ruby (Rails app, matches repo's existing Ruby/Rails version — no version
change)

**Primary Dependencies**: Existing Rails models/concerns only (`ActiveRecord`, `RubyLLM::Tool` base
class already used by `custom/app/services/custom/scout/tools/`); no new gems.

**Storage**: PostgreSQL — no schema changes. Reuses existing tables: `ichatr_scouts`,
`ichatr_pipeline_stages` (via core `pipeline_stages`), `ichatr_pipeline_stage_required_fields`,
`ichatr_scout_required_fields`, `opportunities`, `custom_attribute_definitions`.

**Testing**: RSpec, under `custom/spec/services/custom/scout/` (existing convention for this
module) — `bundle exec rspec custom/spec/`.

**Target Platform**: Existing Rails monolith backend (no frontend/Vue surface for this feature —
all consumption is by the Scout LLM agent at conversation-turn time).

**Project Type**: Backend service extension inside an existing fork-specific module
(`custom/app/services/custom/scout/`, `custom/app/models/`) — not a new project/app.

**Performance Goals**: No new performance targets. Prompt-building and stage-transition checks read
already-loaded/small per-account config tables (stage count and required-field count are small,
bounded by what an operator configures in the existing Kanban/Scout UI) — must not introduce
N+1 queries into the per-turn system-prompt build beyond what `PipelineStage.ordered_for_account`
style eager loading already supports.

**Constraints**: Must not change behavior for backward/lateral stage moves or opportunity creation
(FR-012, FR-013). Must not allow any code path to bypass the checks enforced by
`OpportunityStageTransitionService` (FR-008). Must not regress `HandoverToHuman`'s existing
behavior (team/assignee assignment, conditional `bot_handoff!`, conditional transfer note,
conditional contact memory) when its logic is extracted into `HandoffService`.

**Scale/Scope**: Per-conversation, per-account; no multi-tenant fan-out concerns beyond what
already exists for Scout tool calls.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First** — PASS. All new/changed code lives entirely inside the
  fork-specific `custom/` tree (`custom/app/services/custom/scout/`,
  `custom/app/services/custom/scout/tools/`). No upstream/core file is renamed or restructured; the
  only touched file outside the tool/service files themselves is the existing
  `Custom::Scout::SystemPromptsService`, which is itself a fork-owned class already extended
  additively in prior phases (Fase 08). No new extension points are needed since this whole domain
  (Scout, Opportunity, PipelineStage) is fork-native, not an upstream Chatwoot concept.
- **II. Smallest Production-Ready Change** — PASS. Reuses the existing model-level validation
  (`Custom::Concerns::OpportunityValidations#validate_forward_stage_move_requirements`) for
  stage-specific required fields instead of re-implementing that check; only extracts
  `HandoffService` because it now has two real callers (the tool and the new transition service),
  not speculatively.
- **III. Adhere to Established Conventions** — PASS. Pure Ruby/RSpec change following existing
  RuboCop conventions in `custom/`; no Vue/JS/Tailwind surface is touched by this feature.
- **IV. Safe, Reversible Change Management** — PASS. No migrations, no destructive operations; the
  `move_opportunity_stage` tool's `lost_reason` parameter removal is a same-PR contract change to a
  tool that has not shipped a load-bearing "lost" workflow (that path is being deliberately removed
  as incorrect per this feature's own decisions), not a removal of external API surface.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — N/A. Scout, Opportunity, and the pipeline/funnel
  domain are fork-only (`custom/`) concepts with no upstream OSS or `enterprise/` equivalent to
  keep in sync.

No violations. Complexity Tracking table is not needed.

## Project Structure

### Documentation (this feature)

```text
specs/052-scout-qualification-gate/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   └── scout-tools.md
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
custom/
├── app/
│   ├── models/
│   │   ├── scout.rb                                          # existing — read-only for this feature
│   │   ├── scout_required_field.rb                            # existing — read-only for this feature
│   │   ├── pipeline_stage.rb                                   # existing — read-only for this feature
│   │   ├── pipeline_stage_required_field.rb                    # existing — read-only for this feature
│   │   ├── opportunity.rb                                      # existing — read-only for this feature
│   │   └── custom/concerns/opportunity_validations.rb          # existing — read-only, reused as-is
│   └── services/
│       └── custom/scout/
│           ├── system_prompts_service.rb                       # MODIFIED — add funnel_section
│           ├── agent_runner.rb                                 # unchanged (already exposes scout.account)
│           ├── handoff_service.rb                               # NEW — extracted from HandoverToHuman
│           ├── opportunity_stage_transition_service.rb          # NEW — single stage-change enforcement point
│           └── tools/
│               ├── move_opportunity_stage.rb                    # MODIFIED — drop lost_reason, delegate to service
│               ├── manage_opportunity.rb                        # MODIFIED — delegate stage_id changes to service
│               └── handover_to_human.rb                         # MODIFIED — thin wrapper around HandoffService
└── spec/
    ├── models/
    │   └── custom/concerns/opportunity_validations_spec.rb      # existing — no change expected
    └── services/
        └── custom/scout/
            ├── system_prompts_service_spec.rb                   # MODIFIED — cover funnel_section
            ├── handoff_service_spec.rb                          # NEW
            ├── opportunity_stage_transition_service_spec.rb     # NEW
            └── tools/
                ├── move_opportunity_stage_spec.rb                # MODIFIED
                ├── manage_opportunity_spec.rb                    # MODIFIED
                └── handover_to_human_spec.rb                     # MODIFIED
```

**Structure Decision**: This is a backend-only extension of the existing fork-specific `custom/`
module (mirrors the layout already used by Fases 02/05/08 of the Scout feature line). No new
top-level directory, no frontend (`app/javascript`) changes, no migrations. All new classes are
namespaced under `Custom::Scout::`, matching the existing `HandoverToHuman`,
`ContactNotesService`, and `SystemPromptsService` precedent.

## Complexity Tracking

*No Constitution Check violations — table intentionally omitted.*
