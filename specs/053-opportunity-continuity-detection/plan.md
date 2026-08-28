# Implementation Plan: Opportunity Continuity Detection

**Branch**: `053-opportunity-continuity-detection` | **Date**: 2026-08-27 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/053-opportunity-continuity-detection/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Give the two existing deal-creation entry points — the Scout tool `manage_opportunity` and the
automation-rule action `create_opportunity` — a shared, deterministic way to decide whether a
contact's *other* open deals mean "reuse this one" or "this is genuinely new," instead of each one
only recognizing a deal already tied to the current conversation. The fix is one new shared service
(`Custom::Opportunities::ContinuityResolverService`) implementing the 3-branch funnel from the
source design (0 candidates → create; a validated declared match → reuse; anything else with
candidates present → ambiguous, flagged via a private note), called identically from both entry
points. The Scout path additionally gains a new optional `opportunity_id` tool parameter (the
"declared match") and gets the contact's open deals exposed as structured system-prompt context
(mirroring the existing funnel-stage context pattern), plus a guardrail-text reinforcement to call
`manage_opportunity` at any point in a conversation. The automation-rule path never has a declared
match to offer, so it permanently exercises the funnel's "no declaration" branch: create only when
zero open deals exist, flag otherwise — no rule-specific shortcut, per the resolved design
ambiguity from `/speckit-clarify`.

## Technical Context

**Language/Version**: Ruby 3.4.4 (Rails 7.1)

**Primary Dependencies**: Rails 7.1 / ActiveRecord (existing `Opportunity`, `OpportunityConversation`
models); RubyLLM (`Custom::Scout::Tools::BaseTool < RubyLLM::Tool` — the tool-calling interface the
Scout LLM uses); existing `Messages::MessageBuilder` for private-note creation.

**Storage**: PostgreSQL — existing `ichatr_opportunities` / `ichatr_opportunity_conversations`
tables. No schema changes (spec's Out of Scope explicitly rules out new `Opportunity` columns).

**Testing**: RSpec, under `custom/spec/services/...`, matching the existing specs for
`Custom::Scout::Tools::ManageOpportunity` and `Custom::AutomationRules::ActionService`.

**Target Platform**: Existing Rails backend (chatwoot monolith) — no new deployable unit, no
frontend changes (spec's Out of Scope: no new UI).

**Project Type**: Single project (Rails monolith), backend-only change.

**Performance Goals**: N/A beyond the existing synchronous request path — deal creation/update
already happens inline during Scout tool execution and automation-rule execution today; this
feature adds one additional scoped `WHERE contact_id = ? AND status = 'open'` lookup to each path,
not a new performance envelope.

**Constraints**: Must live entirely in the fork's `custom/` tree, wired through existing extension
points (Constitution Principle I); the two call sites MUST invoke one identical shared decision
rule rather than duplicated logic (spec FR-008 requires this explicitly, and Constitution Principle
II disfavors the two copies drifting apart over time); no new `Opportunity` model fields.

**Scale/Scope**: One new shared service; edits to two existing call sites
(`Custom::Scout::Tools::ManageOpportunity`, `Custom::AutomationRules::ActionService#create_opportunity`);
one new structured context section in `Custom::Scout::SystemPromptsService`; a guardrail-text
addition. No new top-level models, no migrations, no new routes/controllers.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First** — PASS. All new code lives under `custom/app/services/custom/`
  (new `Custom::Opportunities::` namespace, sibling to the existing `Custom::Scout::` and
  `Custom::AutomationRules::` namespaces). The only touched files are already fork-owned:
  `Custom::Scout::Tools::ManageOpportunity`, `Custom::Scout::SystemPromptsService`, and the
  `Custom::AutomationRules::ActionService` module (itself an extension point already wired into
  core via `prepend_mod_with` in `app/services/automation_rules/action_service.rb`). No core
  Chatwoot file is edited.
- **II. Smallest Production-Ready Change** — PASS. A single shared resolver service is the smaller
  change relative to the alternative (duplicating the funnel in both call sites): the spec (FR-008)
  requires the two paths to apply the *identical* rule, and identical logic kept in one place is
  the more minimal, less error-prone way to guarantee that than two hand-synced copies.
- **III. Adhere to Established Conventions** — PASS. New service follows the existing plain
  Ruby service-object shape already used throughout `custom/app/services/custom/` (see
  `Custom::Scout::OpportunityStageTransitionService`, `Crm::Leadsquared::LeadFinderService`); RSpec
  specs follow existing conventions in `custom/spec/services/`.
- **IV. Safe, Reversible Change Management** — PASS. No destructive or irreversible operations;
  standard reads and record creates/updates through existing model validations.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — PASS / N/A. Confirmed no `enterprise/` file
  references `Opportunity`, `AutomationRules::ActionService#create_opportunity`, or Scout —
  `enterprise/app/services/enterprise/action_service.rb` only adds `add_sla`, unrelated to this
  feature. The Kanban/Opportunity module is entirely fork-specific with no enterprise counterpart.

No violations to record in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/053-opportunity-continuity-detection/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
custom/app/services/custom/
├── opportunities/                              # NEW namespace, sibling to scout/ and automation_rules/
│   └── continuity_resolver_service.rb          # NEW — shared 3-branch funnel, used by both call sites below
├── scout/
│   ├── tools/
│   │   └── manage_opportunity.rb               # MODIFIED — new opportunity_id param, calls resolver, ambiguous → private note
│   └── system_prompts_service.rb               # MODIFIED — new structured "open deals" context section; guardrail text tweak
└── automation_rules/
    └── action_service.rb                       # MODIFIED — #create_opportunity calls the same resolver

custom/spec/services/custom/
├── opportunities/
│   └── continuity_resolver_service_spec.rb      # NEW
├── scout/
│   ├── tools/manage_opportunity_spec.rb         # MODIFIED — new scenarios (reuse / ambiguous / validation)
│   └── system_prompts_service_spec.rb           # MODIFIED (if present) — new context section coverage
└── automation_rules/action_service_spec.rb      # MODIFIED — reuse / ambiguous scenarios for create_opportunity
```

**Structure Decision**: Single Rails monolith project, no frontend or new deployable component.
The feature is implemented as one new shared service in a new `Custom::Opportunities::` namespace
(mirroring the existing sibling namespaces `Custom::Scout::` and `Custom::AutomationRules::` already
under `custom/app/services/custom/`), consumed by the two existing deal-creation call sites. This
keeps the funnel logic in exactly one place, satisfying FR-008's "identical decision rule, no
rule-specific shortcut" requirement without introducing a new top-level tree, model, or migration.

## Complexity Tracking

*No entries — Constitution Check has no violations requiring justification.*
