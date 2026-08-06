# Implementation Plan: Contact Panel Opportunities Section

**Branch**: `020-contact-panel-opportunities` | **Date**: 2026-08-05 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/020-contact-panel-opportunities/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Add an "Opportunities" accordion section to the conversation contact panel, listing the current contact's opportunities most-recent-first (mirroring the existing "previous conversations" section), and upgrade the shared `OpportunityBackfillModal.vue` (already used from the kanban board) so it becomes a full editing surface — stage change, reopen, deal value, and all custom attributes — reachable directly from that new section without leaving the conversation.

## Technical Context

**Language/Version**: Ruby (Rails, existing app version) for backend; Vue 3 (Composition API, `<script setup>`) for frontend — matching the rest of this repo.

**Primary Dependencies**: Existing in-repo pieces only — `Api::V1::Accounts::OpportunitiesController` (backend filtering), `Concerns::KanbanFeatureGuard`, the Vuex `opportunities` store module (`byId`/`idsByStage`/getters pattern), `useUISettings.js` (sidebar section registry + accordion open-state), `ContactPanel.vue`/`ContactConversations.vue` (reference pattern for the new section), `OpportunityBackfillModal.vue`, `OpportunityRequiredFieldsForm.vue`, `KanbanCard.vue` (card-field badge logic to extract), `pipelineStages/stagesSortedByPosition` and `pipelineStages/stageById` getters, `pipelineCardFieldConfigs`/`pipelineCurrency` getters. No new external libraries.

**Storage**: PostgreSQL, via the existing fork-prefixed `matias_opportunities` table (`custom/app/models/opportunity.rb`). No schema changes — this feature only adds a read filter (`contact_id`) and reuses the existing update path.

**Testing**: RSpec (`bundle exec rspec`) for the backend controller filter (extending `spec/requests/api/v1/accounts/opportunities_controller_spec.rb`). No new frontend test files, per this project's convention of avoiding specs unless explicitly requested (`CLAUDE.md`), though the existing `KanbanBoard.spec.js` suite must keep passing after the `KanbanCard.vue` refactor.

**Target Platform**: Chatwoot dashboard SPA + Rails API, within this personal fork's existing account/opportunity infrastructure (all backend logic under `custom/`, no `enterprise/` involvement — confirmed no `Opportunity`/opportunities-controller overrides exist under `enterprise/`).

**Project Type**: Web application (existing Rails + Vue monolith) — backend under `custom/app/controllers`, frontend under `app/javascript/dashboard`.

**Performance Goals**: N/A — a single contact's opportunity list is expected to stay small (per spec Assumptions); standard CRUD/list-render latency already met by the surrounding code, no new performance-sensitive path introduced.

**Constraints**: Backend change stays inside the fork's existing `custom/` isolation (`OpportunitiesController` already lives there, not upstream). Frontend changes extend OSS dashboard files/directories a prior phase already established as the fork's opportunities UI surface (`app/javascript/dashboard/components-next/Opportunities/`, `app/javascript/dashboard/store/modules/opportunities/`) rather than introducing new core-file coupling. The `ContactPanel.vue` sidebar chain and `DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER` array are both closed, upstream-owned structures requiring a direct new-entry edit (same class of edit already made for other synced sections like `shopify_orders`/`linear_issues`) rather than a refactor of the chain itself.

**Scale/Scope**: One new backend query filter, one new Vuex action/getter pair, one new sidebar entry + accordion branch, two new Vue components (`ContactOpportunities.vue`, `ContactOpportunityCard.vue`), one new composable (`useOpportunityCardFields`), and a scoped upgrade to one existing modal (`OpportunityBackfillModal.vue`) plus its underlying update payload. No new endpoints beyond the `contact_id` filter param on the existing `index` action.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Result |
|---|---|---|
| I. Upstream Compatibility First | Backend change is a filter param added to `custom/app/controllers/api/v1/accounts/opportunities_controller.rb`, which does not exist upstream — no core file touched. Frontend changes either add new files under the fork's own `components-next/Opportunities/` and `composables/` directories, or make direct, additive entries into two upstream-owned closed structures (`DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER`, `ContactPanel.vue`'s `v-if`/`v-else-if` chain) — the same pattern already used for every other synced sidebar section (`shopify_orders`, `linear_issues`, etc.), not a restructuring of either file. | PASS |
| II. Smallest Production-Ready Change | Scope is exactly the spec's 19 FRs: one filter, one section, one card component, one modal upgrade reused by both entry points. No new permission layer, no notifications, no pagination, no new opportunity-creation entry point — all explicitly out of scope per the spec. | PASS |
| III. Adhere to Established Conventions | New Vue components follow existing Composition-API/`<script setup>` conventions from `ContactConversations.vue`/`KanbanCard.vue`; Tailwind-only styling matching `OpportunityBackfillModal.vue`'s existing utility classes; i18n keys added to `en.yml`/`en.json` only, no bare strings; Ruby stays within existing RuboCop-compliant controller/model conventions. | PASS |
| IV. Safe, Reversible Change Management | No destructive operations; no migrations required; the `KanbanCard.vue` card-field-badge extraction is a same-behavior refactor covered by the existing `KanbanBoard.spec.js` suite. | PASS |
| V. Dual-Tree Awareness (OSS + Enterprise) | Confirmed no `enterprise/` overrides of `Opportunity`, `OpportunitiesController`, or any opportunities Vue component exist — this feature has no enterprise surface to keep in sync. | PASS (N/A) |

No violations; Complexity Tracking section is not needed.

**Post-Phase 1 re-check**: Design artifacts (`research.md`, `data-model.md`, `contracts/`, `quickstart.md`) introduced no new entities, endpoints, or cross-cutting structures beyond what Technical Context already anticipated — the `contact_id` filter and extended update payload stay inside the existing controller/model, and every new frontend file stays inside the fork's established `components-next/Opportunities/`, `composables/`, and `store/modules/opportunities/` directories. All five principles remain PASS with no changes to the assessment above.

## Project Structure

### Documentation (this feature)

```text
specs/020-contact-panel-opportunities/
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
└── app/
    └── controllers/api/v1/accounts/
        └── opportunities_controller.rb        # index: accept contact_id filter param

spec/requests/api/v1/accounts/
└── opportunities_controller_spec.rb           # existing coverage to extend for contact_id filter

app/javascript/dashboard/
├── composables/
│   ├── useUISettings.js                       # DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER: add 'previous_opportunities'
│   └── useOpportunityCardFields.js             # NEW — configuredFields/pipelineCurrency/cardFieldConfigs/statusBadgeClass/isStale, extracted from KanbanCard.vue
├── routes/dashboard/conversation/
│   ├── ContactPanel.vue                        # add v-else-if branch for 'previous_opportunities', gated by FEATURE_FLAGS.OPPORTUNITIES
│   └── ContactOpportunities.vue                 # NEW — mirrors ContactConversations.vue; fetchForContact on mount/contactId change
├── components-next/Opportunities/
│   ├── KanbanCard.vue                           # refactor: use useOpportunityCardFields instead of inline logic
│   ├── ContactOpportunityCard.vue               # NEW — title/status/dates/stage/badges; opens OpportunityBackfillModal on click
│   ├── OpportunityBackfillModal.vue             # upgrade: stage selector/reopen, always-visible deal value, all custom attributes
│   └── OpportunityRequiredFieldsForm.vue        # no changes (already supports required/optional split)
├── store/modules/opportunities/
│   ├── actions.js                               # fetchForContact({ contactId })
│   ├── mutations.js                             # SET_IDS_BY_CONTACT (mirrors SET_IDS_BY_STAGE)
│   └── getters.js                               # cardsForContact
└── i18n/locale/en/
    └── ...opportunities.json / conversation sidebar keys # new accordion title + reopen/stage-select i18n keys
```

**Structure Decision**: Standard Chatwoot web-app split already used by this fork — the one backend change lives under the fork's isolated `custom/app/controllers/**` (Constitution Principle I), and all frontend changes live in the existing `app/javascript/dashboard/**` locations prior opportunities phases already established, plus two direct, additive entries into the two closed upstream structures (`useUISettings.js`'s order array, `ContactPanel.vue`'s branch chain) that this class of section has always required. No `enterprise/` involvement; no new top-level directories.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
