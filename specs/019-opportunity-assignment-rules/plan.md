# Implementation Plan: Opportunity Assignment Rules

**Branch**: `019-opportunity-assignment-rules` | **Date**: 2026-08-05 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/019-opportunity-assignment-rules/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Let opportunity ownership actually be set. Add an `assignee_id` choice (a specific agent/administrator, or "same as the conversation") to the existing `create_opportunity` automation action, and add a plain assignee field to the opportunity create and edit views. Land this alongside the fix for a pre-existing bug where the automation action's stage selector wrote a config shape (`{ id, name }`) the backend never read (`params[:pipeline_stage_id]`), so `Opportunity.create!` always raised and no opportunity was ever created by that action.

## Technical Context

**Language/Version**: Ruby (Rails, existing app version) for backend; Vue 3 (Composition API, `<script setup>`) for frontend — matching the rest of this repo.

**Primary Dependencies**: Existing in-repo pieces only — `Custom::AutomationRules::ActionService` (backend action execution), `AutomationRule`/`Custom::AutomationRule` (action registration), the dashboard's `AutomationActionInput.vue` + `constants.js` automation config framework, `useAutomationValues.js` (dropdown data), Vuex `opportunities` store module, `SingleSelect` component. No new external libraries.

**Storage**: PostgreSQL, via the existing fork-prefixed `matias_opportunities` table. `Opportunity.assignee_id` / `belongs_to :assignee` already exist in the schema and model (`custom/app/models/opportunity.rb`) — no migration needed.

**Testing**: RSpec (`bundle exec rspec`) for backend (`Custom::AutomationRules::ActionService`) only, extending existing coverage for the method whose behavior changes. No new frontend test files, per this project's convention of avoiding specs unless explicitly requested (`CLAUDE.md`).

**Target Platform**: Chatwoot dashboard SPA + Rails API, within this personal fork's existing account/automation/opportunity infrastructure (all under `custom/`, no enterprise involvement — confirmed no `Opportunity`/automation overrides exist under `enterprise/`).

**Project Type**: Web application (existing Rails + Vue monolith) — backend under `custom/app/{models,services,controllers}`, frontend under `app/javascript/dashboard`.

**Performance Goals**: N/A — standard CRUD/dropdown-latency expectations already met by the surrounding code; no new performance-sensitive path introduced.

**Constraints**: Backend logic stays inside the fork's existing `custom/` isolation (already the case for `Opportunity`, `OpportunitiesController`, `Custom::AutomationRules::ActionService`). Frontend changes extend OSS dashboard files (`constants.js`, `AutomationActionInput.vue`, `useAutomationValues.js`, `OpportunityCreateModal.vue`, `OpportunityBackfillModal.vue`) that a prior phase already established as the fork's automation/opportunity UI surface — this continues that existing pattern rather than introducing new core-file coupling.

**Scale/Scope**: Single automation action config field, two modal form fields, one bug fix in an existing service method. No new endpoints (`assignee_id` is already a permitted param on both create and update actions of `OpportunitiesController`).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Result |
|---|---|---|
| I. Upstream Compatibility First | All backend changes stay inside `custom/` (`Custom::AutomationRules::ActionService`, `Opportunity`, `OpportunitiesController` — none of these exist upstream). Frontend changes edit existing fork-added sections of OSS dashboard files (the `create_opportunity` action config, opportunity modals) rather than restructuring or renaming anything upstream owns. | PASS |
| II. Smallest Production-Ready Change | Scope is exactly the spec's 9 FRs: one automation config field, one bug fix, two modal fields. No notification system, no permission layer, no ownership-group concept — all explicitly deferred per the spec's Assumptions. | PASS |
| III. Adhere to Established Conventions | Vue changes follow the existing `AutomationActionTeamMessageInput.vue` pattern (Composition-API-adjacent, `modelValue`/`update:modelValue`), reuse `SingleSelect`/native `<select>` per the existing modals' own conventions, and add i18n keys to `en.yml`/`en.json` only. Ruby changes stay within existing RuboCop-compliant service/controller/model files. | PASS |
| IV. Safe, Reversible Change Management | No destructive operations; no migrations required (columns already exist). | PASS |
| V. Dual-Tree Awareness (OSS + Enterprise) | Confirmed no `enterprise/` overrides of `Opportunity`, `OpportunitiesController`, `Custom::AutomationRules::ActionService`, or `AutomationRule` exist — this feature has no enterprise surface to keep in sync. | PASS (N/A) |

No violations; Complexity Tracking section is not needed.

**Post-Phase 1 re-check**: Design artifacts (`data-model.md`, `contracts/`) introduced no new entities, endpoints, or cross-tree coupling beyond what Phase 0 anticipated — the only concrete addition surfaced during design is extending the `opportunities/create` Vuex action's payload whitelist (a same-file, same-pattern edit). All five gates remain PASS.

## Project Structure

### Documentation (this feature)

```text
specs/019-opportunity-assignment-rules/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
custom/
├── app/
│   ├── models/
│   │   └── opportunity.rb                          # existing: assignee_id/belongs_to :assignee already present
│   ├── services/custom/automation_rules/
│   │   └── action_service.rb                        # create_opportunity: read assignee_id, fix pipeline_stage_id bug
│   └── controllers/api/v1/accounts/
│       └── opportunities_controller.rb               # existing: assignee_id already permitted, no changes expected

spec/services/automation_rules/
└── action_service_spec.rb                            # existing coverage of create_opportunity to extend

app/javascript/dashboard/
├── routes/dashboard/settings/automation/
│   └── constants.js                                  # create_opportunity inputType: 'search_select' -> 'create_opportunity'
├── components/widgets/
│   ├── AutomationActionInput.vue                      # add branch for new inputType
│   └── AutomationActionCreateOpportunityInput.vue      # NEW — pipeline stage + assignee SingleSelects
├── composables/
│   └── useAutomationValues.js                         # getActionDropdownValues: return agents alongside pipelineStages for create_opportunity
├── helper/
│   └── automationHelper.js                            # getActionOptions dropdown wiring for the new inputType
├── components-next/Opportunities/
│   ├── OpportunityCreateModal.vue                      # add Assignee <select>, include assignee_id in create dispatch
│   └── OpportunityBackfillModal.vue                     # add Assignee <select>, include assignee_id in update dispatch
├── store/modules/opportunities/
│   └── actions.js                                     # create action: forward assigneeId -> assignee_id (currently whitelists fields, drops it)
└── i18n/locale/en/
    ├── automation.json (or en.yml automation keys)      # new assignee dropdown / "Mesmo da conversa" label keys
    └── ...opportunities.json                            # new Assignee field labels for both modals
```

**Structure Decision**: Standard Chatwoot web-app split already used by this fork — fork-specific backend logic lives under `custom/app/**` (isolated per Constitution Principle I), and frontend changes live in the existing `app/javascript/dashboard/**` locations this feature's predecessor (Phase 12, opportunity-triggered automations) already established for opportunity/automation UI. No `enterprise/` involvement; no new top-level directories.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
