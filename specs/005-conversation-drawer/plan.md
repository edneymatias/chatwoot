# Implementation Plan: Conversation Drawer on Card Click

**Branch**: `005-conversation-drawer` | **Date**: 2026-07-31 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/005-conversation-drawer/spec.md`

## Summary

Replace `OpportunityDetailView.vue` (a metadata-only side panel that links away to the standalone
conversation view) with an in-context drawer that opens the real conversation experience — message
thread + native contact sidebar, no conversation list — on top of the Kanban board when a card with
a linked conversation is clicked. The drawer is a Vue Router child route nested under
`opportunities_index` (`opportunities/conversations/:conversationId`, name
`opportunities_conversation`), so it is deep-linkable and closable via back navigation. A new
composable `useConversationDrawer.js` is the single integration point with the existing "active
chat" Vuex state (`setActiveChat`/`clearSelectedState`, the existing `getConversation` fetch action,
and `markMessagesRead`), reusing `ConversationBox.vue` and `ConversationSidebar.vue` exactly as
`ConversationView.vue` already does, with zero edits to those shared components. Cards without
`origin_conversation_id` become visually muted and non-interactive.

## Technical Context

**Language/Version**: JavaScript (Vue 3, Composition API with `<script setup>`); no backend/Ruby
changes (per FR out-of-scope and Assumptions in spec.md)

**Primary Dependencies**: Vue Router 4 (nested/child routes), Vuex 4 (`conversations` store module),
existing `ConversationBox.vue` and `ConversationSidebar.vue` components, existing `opportunities`
Vuex store module

**Storage**: N/A — no new persisted data; reuses existing `Conversation`/`Opportunity` records via
already-existing store actions

**Testing**: `pnpm eslint` and `pnpm test` (Vitest) inside the `vite` container, per this repo's
standard JS quality gates and this feature's own Completion Criteria

**Target Platform**: Web dashboard (browser), existing Chatwoot `app/javascript/dashboard` SPA

**Project Type**: Web application — frontend-only change within the existing dashboard frontend
(no separate backend/frontend split to choose between; this repo's `app/javascript/dashboard` *is*
the frontend)

**Performance Goals**: N/A beyond standard SPA responsiveness already provided by
`ConversationBox`/`ConversationSidebar`; no new performance targets introduced

**Constraints**: Must not modify `ConversationBox.vue`, `ConversationSidebar.vue`, or
`ConversationView.vue` (FR-004, Assumptions); `dashboard.routes.js` changes must follow the
existing anchor-based touch pattern in `bin/sync-custom-module-hooks` (its inline manifest must
gain a new entry, per the source phase doc's FR-001); all Vuex "active chat" coupling must funnel
through the single new `useConversationDrawer.js` composable (FR-005/FR-006/FR-007)

**Scale/Scope**: Small, frontend-only surface: 1 new route entry, 1 new component
(`OpportunityConversationDrawer.vue`), 1 new composable (`useConversationDrawer.js`), edits to
`KanbanCard.vue` and `KanbanBoard.vue`, 1 manifest entry in `bin/sync-custom-module-hooks`, deletion
of `OpportunityDetailView.vue`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First (NON-NEGOTIABLE)** — PASS. `ConversationBox.vue`,
  `ConversationSidebar.vue`, and `ConversationView.vue` (all upstream-shaped core files) are reused
  as-is with zero edits (FR-004, confirmed reusable via research: `ConversationView.vue` already
  composes these exact components off `currentChat`/`uiSettings`). The only core file touched is
  `dashboard.routes.js`, and only through the same anchor-based insert pattern already established
  by the prior `opportunities_index` route addition in `bin/sync-custom-module-hooks` — not a raw
  hand-edit. `OpportunityDetailView.vue`, `KanbanCard.vue`, `KanbanBoard.vue`, and the new
  composable/component all live inside this fork's own `Opportunities/` module tree, which is
  itself additive to upstream (upstream has no Kanban board), so deleting/editing files inside it
  carries no upstream-merge risk.
- **II. Smallest Production-Ready Change** — PASS. No new abstractions beyond what FR-004/FR-005
  explicitly require (one drawer component, one composable). No speculative "link conversation
  later" flow, no toast fallback, no ContactPanel Opportunities section — all explicitly deferred
  per spec.md Assumptions and the source doc's Out of Scope.
- **III. Adhere to Established Conventions** — PASS. New Vue files use Composition API with
  `<script setup>`; Tailwind-only styling for the opacity/affordance changes on non-clickable cards
  (FR-003); i18n for the inline error message and close action (FR-008) instead of bare strings;
  PascalCase component name (`OpportunityConversationDrawer.vue`), camelCase composable/events.
- **IV. Safe, Reversible Change Management** — PASS. All changes are local file edits/additions
  plus one deletion of a file with no other referrers (confirmed via research: only
  `KanbanBoard.vue` imports `OpportunityDetailView.vue`); fully reversible via git, no destructive
  or shared-state operations involved.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — PASS. The Opportunities/Kanban module is a
  fork-specific addition with no upstream or `enterprise/` counterpart (confirmed: no
  `enterprise/` overrides exist for `Opportunities/`, `ConversationView.vue`, `ConversationBox.vue`,
  or `ConversationSidebar.vue` in this fork). No dual-tree decision is required for this feature.

No violations — Complexity Tracking table is not needed.

**Post-Design Re-check** (after Phase 1 `data-model.md`/`quickstart.md`): No new files, entities,
or coupling points were introduced beyond what was already gated above — the drawer state model in
`data-model.md` is entirely client-side and internal to `useConversationDrawer.js`, and no
`/contracts/` were needed (no new external interfaces). All five principles remain PASS.

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
app/javascript/dashboard/components-next/Opportunities/
├── KanbanBoard.vue                      # edit: render drawer route-view instead of local selectedOpportunityId panel
├── KanbanColumn.vue                     # unchanged (already forwards card `click` event)
├── KanbanCard.vue                       # edit: opacity-60 + no click affordance when no origin_conversation_id
├── OpportunityDetailView.vue            # delete (FR-010)
└── OpportunityConversationDrawer.vue    # new: right-side panel composing ConversationBox + ConversationSidebar

app/javascript/dashboard/composables/
└── useConversationDrawer.js             # new: single coupling point to active-chat Vuex state

app/javascript/dashboard/routes/dashboard/
└── dashboard.routes.js                  # edit (via bin/sync-custom-module-hooks anchor pattern): add
                                          # `opportunities_conversation` child route under `opportunities_index`

bin/
└── sync-custom-module-hooks             # edit: extend inline manifest with the new route anchor/insert entry

app/javascript/dashboard/store/modules/conversations/
└── actions.js                           # unchanged; reuse existing getConversation / setActiveChat /
                                          # clearSelectedState actions as-is (no new store code)
```

**Structure Decision**: Pure frontend change inside the existing Chatwoot dashboard SPA
(`app/javascript/dashboard/`) — no backend, no separate frontend/backend split to choose between.
New files live inside the fork's own `Opportunities/` module tree (drawer component) and the
existing shared `composables/` directory (drawer composable), consistent with how this module was
built in prior phases. The only core/shared file touched is `dashboard.routes.js`, and only via the
already-established anchor-based insert pattern in `bin/sync-custom-module-hooks`, whose manifest
gains one new entry for this feature.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
