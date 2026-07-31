# Implementation Plan: Automation Integration — Create Opportunity Action

**Branch**: `002-automation-integration` | **Date**: 2026-07-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-automation-integration/spec.md`

## Summary

Register a new `create_opportunity` Automation Rule action that reuses Chatwoot's existing
`AutomationRule`/`AutomationRules::ActionService` engine end-to-end. No new trigger, condition
type, or bespoke settings screen is introduced — an admin picks any existing trigger event and
condition set through the standard Automation Rules flow and adds `create_opportunity` as an
action alongside `add_label`/`assign_agent`/etc. The action creates one `Opportunity` (Phase 1
model) in the configured `PipelineStage`, is idempotent per originating conversation (enforced at
the database level via a partial unique index, not just an application-level check), and
propagates failures through the existing per-action rescue/`ChatwootExceptionTracker` path. The
only edit to a pre-existing core file is a single `prepend_mod_with` line added to
`app/services/automation_rules/action_service.rb`, since — unlike `AutomationRule`/`Contact` —
that class currently has no extension seam.

## Technical Context

**Language/Version**: Ruby (Rails 7.1, matches repo's existing `Gemfile`/`schema.rb` version)

**Primary Dependencies**: Rails (ActiveRecord), existing `AutomationRule`/`AutomationRules::ActionService`
engine, `ChatwootExceptionTracker` (existing per-action error capture), Phase 1's `Opportunity`/
`PipelineStage` models (`custom/app/models/`)

**Storage**: PostgreSQL (existing `db/schema.rb`); one new additive migration adding a partial
unique index (`WHERE origin_conversation_id IS NOT NULL`) on `matias_opportunities.origin_conversation_id`
— no new tables, no changes to any existing table's columns

**Testing**: RSpec (`bundle exec rspec`), run inside the `rails` container per `CLAUDE.md`; extend
`spec/services/automation_rules/action_service_spec.rb` and `spec/models/automation_rule_spec.rb`
with a `create_opportunity` context; no JS/Vue testing this phase (no frontend code — Phase 3)

**Target Platform**: Existing Chatwoot Rails monolith, Docker/Podman Compose dev stack

**Project Type**: Web application (Rails backend only, this phase — no frontend)

**Performance Goals**: N/A — this action runs synchronously within the existing per-action loop
in `AutomationRules::ActionService#perform`, same cost profile as any other existing action (e.g.
`add_label`); no new performance targets

**Constraints**: Zero edits to `app/models/automation_rule.rb` (FR-001 of the source doc); the
*only* core-file edit permitted is the single `prepend_mod_with('AutomationRules::ActionService')`
line in `app/services/automation_rules/action_service.rb`; all new action logic lives under
`custom/`; idempotency MUST be guaranteed even under concurrent execution (per Clarifications),
which requires a schema-level uniqueness constraint, not application-only checking

**Scale/Scope**: One new automation action, one new `custom/` model-extension module, one new
`custom/` service-extension module, one core-file one-line edit, one migration, one i18n label
entry

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First (NON-NEGOTIABLE)**: PASS. New behavior lives under
  `custom/app/models/custom/automation_rule.rb` and
  `custom/app/services/custom/automation_rules/action_service.rb`, both consumed through the
  existing `prepend_mod_with`/`ChatwootApp.extensions` seam already validated in Phase 1 — zero
  edits to `app/models/automation_rule.rb`. The one edit to
  `app/services/automation_rules/action_service.rb` is the minimum possible: adding the same
  `prepend_mod_with` call pattern that class's siblings (`AutomationRule`, `Contact`) already use,
  not a behavior change to any existing method. The idempotency migration is additive
  (new index only, no column/table changes) and reversible.
- **II. Smallest Production-Ready Change**: PASS. Scope is exactly one action method plus its
  dispatch wiring and one supporting index; no new trigger types, no new condition types, no
  Vue-side rendering (explicitly deferred to Phase 3 per the source doc's Out of Scope section).
- **III. Adhere to Established Conventions**: PASS. `create_opportunity(params)` matches the exact
  dynamic-dispatch contract (`send(action[:action_name], action[:action_params])`) and per-action
  `rescue StandardError` wrapper already used by every other action in
  `AutomationRules::ActionService#perform` — no custom rescue introduced inside the new method
  itself, consistent with how `send_message`/`add_private_note` behave today.
- **IV. Safe, Reversible Change Management**: PASS. The migration only adds a partial unique index
  to the existing `matias_opportunities` table (itself introduced in Phase 1); it is reversible
  and does not touch any pre-existing core table.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS (no Enterprise action needed). Same rationale
  as Phase 1 — this is a personal-fork-only feature under `custom/`, not a core OSS feature
  Enterprise extends or overrides.

No violations. Nothing to record in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/002-automation-integration/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md         # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── create-opportunity-action.md
└── tasks.md              # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
custom/
└── app/
    ├── models/
    │   └── custom/
    │       └── automation_rule.rb           # module Custom::AutomationRule — actions_attributes += create_opportunity
    └── services/
        └── custom/
            └── automation_rules/
                └── action_service.rb         # module Custom::AutomationRules::ActionService#create_opportunity

app/services/automation_rules/action_service.rb  # +1 line: prepend_mod_with('AutomationRules::ActionService')

db/migrate/
└── <timestamp>_add_unique_index_on_matias_opportunities_origin_conversation.rb

app/javascript/dashboard/i18n/locale/en/automation.json   # +1 entry under ACTIONS: CREATE_OPPORTUNITY

spec/
├── services/automation_rules/action_service_spec.rb   # extended with create_opportunity context
└── models/automation_rule_spec.rb                       # extended: actions_attributes includes create_opportunity
```

**Structure Decision**: Continues the `custom/` tree established in Phase 1, mirroring its
`custom/app/models/custom/...` and now adding a parallel `custom/app/services/custom/...`
namespace for the one new service-level extension. No `frontend/`/`backend/` split applies — this
is a backend-only phase (Phase 3 handles the Vue dropdown). The i18n label lives in the frontend
`en.json` tree (not `en.yml`) per this project's established `Backend i18n → en.yml, Frontend
i18n → en.json` convention (see `research.md` — this corrects an inaccuracy in the phase's
original source doc, which referenced `en.yml`).

## Complexity Tracking

*No violations — this section intentionally left without entries.*
