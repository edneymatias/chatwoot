# Implementation Plan: Contact Panel Opportunity Quick Create

**Branch**: `033-contact-panel-opportunity-quick-create` | **Date**: 2026-08-12 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/033-contact-panel-opportunity-quick-create/spec.md`

## Summary

Add an "Add opportunity" action to the Contact Panel's Opportunities section
(`ContactOpportunities.vue`) that opens the existing opportunity creation modal
(`OpportunityCreateModal.vue`) pre-linked to the currently open conversation, with the contact
locked to the conversation's contact. The action is disabled once the current conversation already
has a linked opportunity (enforced today at DB + model level; unchanged here). The Contact Panel's
opportunity list is reordered client-side to surface the opportunity tied to the current
conversation first, visually distinguished, and the list updates immediately after creation via a
new Vuex mutation (`PREPEND_ID_TO_CONTACT`) that closes a gap where newly created opportunities
don't appear in `cardsForContact` until a refetch. All changes are frontend-only (Vue/Vuex); no
backend/API changes.

## Technical Context

**Language/Version**: JavaScript (ES2022+), Vue 3 Composition API with `<script setup>`

**Primary Dependencies**: Vue 3, Vuex 4, vue-i18n; existing `dashboard/components-next/button/Button.vue`

**Storage**: N/A — reuses the existing `Opportunity` model/API and Vuex `opportunities` store module
unchanged; no schema or endpoint changes.

**Testing**: `pnpm test` (Vitest) for component/store specs, run via
`docker compose exec vite pnpm test`

**Target Platform**: Web dashboard SPA (existing Chatwoot conversation view, Contact Panel)

**Project Type**: Frontend-only extension of an existing web application feature (Opportunities /
Kanban module)

**Performance Goals**: No page reload or manual refresh required after creation; list reorder and
highlight are synchronous client-side computations over already-fetched data (no added network
round-trip beyond the existing create request).

**Constraints**: No backend/API/model changes (the one-opportunity-per-conversation rule is
enforced elsewhere and must not be re-implemented here); must not change behavior for any existing
`OpportunityCreateModal` call site (Kanban's per-column "+", the List view's "add opportunity"
button) when `initialContact` is absent.

**Scale/Scope**: 4 files modified (`ContactOpportunities.vue`, `ContactOpportunityCard.vue`,
`OpportunityCreateModal.vue`, `store/modules/opportunities/{actions.js,mutations.js}`), plus i18n
key additions (`en.json`/`pt_BR.json` for frontend strings, mirrored per project convention — this
feature has no backend-facing strings). No new components, routes, or store modules.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. The Opportunities/Kanban module is an existing
  fork-specific feature already living directly under `app/javascript/dashboard/components-next/
  Opportunities/` and `routes/dashboard/conversation/` (frontend customizations in this fork don't
  use a `custom/` tree the way the Ruby backend does — established precedent across features
  001–032). This change extends those same files in place; it does not touch any file that exists
  upstream, and does not rename/relocate anything.
- **II. Smallest Production-Ready Change**: PASS. No new components are introduced; the button,
  prop, mutation, and reorder logic are minimal additions to existing files, mirroring patterns
  already present elsewhere in the same module (`ContactConversations.vue`'s `currentChat` usage,
  `ContactsSidebar/ContactNotes.vue`'s button styling, `PREPEND_ID_TO_STAGE`'s mutation shape).
- **III. Adhere to Established Conventions**: PASS. Composition API + `<script setup>`, Tailwind
  utility classes only, PascalCase components, i18n for all new strings, existing `Button`
  component instead of hand-rolled markup.
- **IV. Safe, Reversible Change Management**: PASS. All changes are additive/local frontend edits;
  no destructive operations involved.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS (no action needed). This is a pure frontend
  UI change with no new endpoint, service, or model — nothing for the `enterprise/` Ruby overlay to
  diverge on. No request/response contract changes.

No violations; Complexity Tracking section is not needed.

## Project Structure

### Documentation (this feature)

```text
specs/033-contact-panel-opportunity-quick-create/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output
├── data-model.md         # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── component-interfaces.md
└── tasks.md             # Phase 2 output (/speckit-tasks command — not created here)
```

### Source Code (repository root)

```text
app/javascript/dashboard/
├── routes/dashboard/conversation/
│   └── ContactOpportunities.vue          # + "Add opportunity" action, reorder/highlight computed,
│                                          #   create-modal wiring, close-on-conversation-change watch
├── components-next/Opportunities/
│   ├── ContactOpportunityCard.vue        # + `isCurrentConversation` prop → accent divider border
│   └── OpportunityCreateModal.vue        # + `initialContact` prop → locked contact chip, no search
└── store/modules/opportunities/
    ├── actions.js                        # `create` action commits new PREPEND_ID_TO_CONTACT
    └── mutations.js                      # + PREPEND_ID_TO_CONTACT mutation

app/javascript/dashboard/i18n/locale/
├── en/{conversation,opportunities}.json  # + new "Add opportunity" action string
└── pt_BR/{conversation,opportunities}.json  # mirrored translation (per project convention)
```

**Structure Decision**: Single frontend project (the existing `app/javascript/dashboard` SPA); no
backend, no new top-level tree. All five touched files already exist and already implement
adjacent parts of the Opportunities feature — this plan only extends them.

## Complexity Tracking

*No violations — section not applicable.*
