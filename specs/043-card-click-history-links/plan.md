# Implementation Plan: Unified Card Click & History Links

**Branch**: `043-card-click-history-links` | **Date**: 2026-09-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/043-card-click-history-links/spec.md`

## Summary

Every Kanban card / list-view row must open something on click — the active conversation if one
exists, otherwise the opportunity's history/activity panel directly (today it's a no-op). Every
conversation-related history entry (opened/transferred-in/transferred-out/detached) becomes a
clickable link to that specific conversation, showing its current status up front, and only when
the current user is actually authorized to view it (otherwise it renders as plain text, same as an
entry whose conversation no longer exists). The click-through and route-optionality work is purely
frontend (`app/javascript/dashboard/...`), reusing an already-authorizing load path. Showing status
and gating link-vs-plain-text requires one small additive enrichment to the existing, fork-owned
`GET .../opportunities/:id/activities` endpoint, computed via the existing `ConversationPolicy` —
no new endpoint, no new persisted data, no policy reimplementation.

## Technical Context

**Language/Version**: Ruby (Rails, repo-pinned version) + Vue 3 (Composition API, `<script setup>`)

**Primary Dependencies**: Rails, Pundit (`ConversationPolicy`), Vue Router 4, Vuex (existing
`getConversationById` / conversation store module)

**Storage**: PostgreSQL (existing tables only — `ichatr_opportunity_activities`, `conversations`;
no migration, see `data-model.md`)

**Testing**: RSpec (`bundle exec rspec`) for the controller enrichment; Vitest (`pnpm test`) for
`KanbanCard.vue`, `OpportunityConversationDrawer.vue`, `OpportunityActivityLog.vue`,
`useConversationDrawer.js` — see `research.md` Unknown 4 (Vitest, not Jest, despite spec.md wording)

**Target Platform**: Existing Chatwoot dashboard (web), Kanban/Opportunities module

**Project Type**: Existing Rails + Vue monolith (fork of Chatwoot) — no new project/service

**Performance Goals**: N/A beyond not introducing N+1 queries in the activities endpoint (batch
Conversation lookups + policy checks for all four event-type entries in one pass, not per-row)

**Constraints**: No new backend endpoint; no change to `ichatr_opportunity_activities` schema or
write-time metadata; must reuse `ConversationPolicy` rather than reimplement access rules
client-side (research.md Unknown 2); must not regress the existing active-conversation click path

**Scale/Scope**: 2 backend files (controller + spec), ~5 frontend files (routes, composable, 3
components) + their specs — see Project Structure below

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. All touched files are either already fork-owned
  (`custom/app/controllers/api/v1/accounts/opportunities/activities_controller.rb`, and the
  `Opportunities/*.vue` components under `app/javascript/dashboard/components-next/`, which are
  fork-created files — Opportunities/Kanban does not exist upstream) or a minimal, already-precedented
  touch to the single shared `dashboard.routes.js` (making one existing fork-added route param
  optional — no restructuring, no upstream route touched). The access-control enrichment reuses the
  existing `ConversationPolicy` class directly instead of reimplementing rules, per the principle's
  preference for extension over reinvention.
- **II. Smallest Production-Ready Change**: PASS. The backend enrichment is the minimum needed to
  satisfy FR-006a/FR-011 without duplicating authorization logic (research.md Unknown 2 rules out
  the client-only alternatives as either incomplete — misses detached conversations — or a
  correctness hazard — reimplementing policy rules in JS). No speculative fields, no new endpoint,
  no new abstraction beyond one enrichment step in an existing controller action.
- **III. Adhere to Established Conventions**: PASS (to be enforced during implementation) —
  RuboCop, ESLint, Composition API/`<script setup>`, i18n for any new user-facing strings (status
  labels — reuse existing conversation-status i18n keys if present rather than adding new ones),
  strong params/PropTypes at boundaries.
- **IV. Safe, Reversible Change Management**: PASS. All changes are additive/reversible file edits;
  no destructive operations, no schema changes.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS. Reusing `ConversationPolicy.new(...).show?`
  directly means the Enterprise-prepended override (`enterprise/app/policies/enterprise/conversation_policy.rb`)
  is honored automatically; no separate Enterprise change is required (research.md Unknown 3).

No violations — Complexity Tracking table is not needed.

*Post-Phase-1 re-check*: data-model.md and contracts/ confirm the design stays additive (no schema
change, one endpoint enriched in place, no new access-control code path). Constitution Check
conclusions above hold unchanged after design.

## Project Structure

### Documentation (this feature)

```text
specs/043-card-click-history-links/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output
├── data-model.md         # Phase 1 output
├── quickstart.md         # Phase 1 output
├── contracts/             # Phase 1 output
│   ├── activities-endpoint.md
│   └── opportunities-conversation-route.md
└── tasks.md              # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

Existing Chatwoot fork monolith — no new top-level directories. Changes land in the existing
locations already used by every prior Kanban/Opportunities phase:

```text
app/javascript/dashboard/
├── routes/dashboard/dashboard.routes.js                         # conversationId param → optional
├── composables/useConversationDrawer.js                         # guard watcher on absent id
├── components-next/Opportunities/
│   ├── KanbanCard.vue                                           # handleCardClick, cardClass
│   ├── OpportunityConversationDrawer.vue                        # activeTab default/watch logic
│   └── OpportunityActivityLog.vue                                # conversation entries → links + status badge
└── routes/dashboard/opportunities/
    ├── Index.vue                                                 # handleRowClick (list view)
    └── components/OpportunityListView.vue                        # row styling (drop grayscale/dashed branch)

custom/app/controllers/api/v1/accounts/opportunities/
└── activities_controller.rb                                      # enrich index response (status + viewable)

custom/spec/requests/api/v1/accounts/opportunities/
└── activities_controller_spec.rb                                 # new/extended coverage for enrichment

(+ corresponding Vitest specs alongside each touched .vue/.js file, per existing convention)

en.json / pt_BR.json                                               # any new status-label / a11y strings, if not already present
```

**Structure Decision**: Follow the structure already established by every earlier Kanban phase in
this repo — fork-created frontend components live in `app/javascript/dashboard/components-next/Opportunities/`
(there is no separate custom frontend tree; Opportunities/Kanban components don't exist upstream, so
placing them in the shared frontend tree doesn't touch any upstream file), while fork-owned backend
code lives under `custom/`, mirroring the `enterprise/` overlay convention. This phase introduces no
new structural pattern.

## Complexity Tracking

*No Constitution Check violations — this section intentionally left empty.*
