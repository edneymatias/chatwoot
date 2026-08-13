# Tasks: Contact Panel Opportunity Quick Create

**Input**: Design documents from `/specs/033-contact-panel-opportunity-quick-create/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/component-interfaces.md, quickstart.md

**Tests**: Not requested for this feature (per project convention: avoid writing specs unless
explicitly asked). Validation is via `quickstart.md` manual scenarios plus existing
lint/test commands in the Polish phase.

**Organization**: Tasks are grouped by user story (US1/US2/US3, priority order from spec.md) to
enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- File paths are relative to `app/javascript/dashboard/` unless otherwise noted

## Phase 1: Setup

- [x] T001 Confirm branch `033-contact-panel-opportunity-quick-create` is checked out and the dev
      stack is running (`docker compose up -d`) with the Opportunities feature flag enabled for
      the test account, per `CLAUDE.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared modal change required by both US1 (pre-fill on open) and US2 (locked/no-search
contact) — must land before either story's Contact Panel wiring is testable end-to-end.

**⚠️ CRITICAL**: Complete before starting US1 or US2.

- [x] T002 Add `initialContact` prop (`{ id, name, email }`, default `null`) to
      `components-next/Opportunities/OpportunityCreateModal.vue`: initialize `selectedContact`
      from it when present, hide the "Clear" button when `initialContact` is set, and confirm the
      search-input branch never renders in that case (contract: `contracts/component-interfaces.md`)

**Checkpoint**: Foundational modal change ready — US1 and US2 implementation can begin.

---

## Phase 3: User Story 1 - Create an opportunity without leaving the conversation (Priority: P1) 🎯 MVP

**Goal**: Agents can create an opportunity from the Contact Panel of an open conversation, without
leaving it, pre-linked to that conversation and pre-filled with its contact.

**Independent Test**: From an open conversation with a contact that has no opportunity linked to
it, click "Add opportunity", complete the flow, and confirm the opportunity is created and linked
to both the contact and the current conversation (see `quickstart.md` Scenario 1).

### Implementation for User Story 1

- [x] T003 [P] [US1] In `routes/dashboard/conversation/ContactOpportunities.vue`, add
      `currentChat` (`useMapGetter('getSelectedChat')`) and `contact`
      (`useMapGetter('contacts/getContact')`, matching `props.contactId`) getters, plus a computed
      `initialContact` object (`{ id, name, email }`) derived from `contact.value`
- [x] T004 [US1] In `routes/dashboard/conversation/ContactOpportunities.vue`, add the
      "Add opportunity" action using `Button` (`variant="link" color="blue" size="sm"
      class="hover:no-underline"`, matching `components-next/Contacts/ContactsSidebar/
      ContactNotes.vue`) plus a local `isCreateModalOpen` ref toggled by the button (depends on T003)
- [x] T005 [US1] In `routes/dashboard/conversation/ContactOpportunities.vue`, render
      `OpportunityCreateModal` (`v-if="isCreateModalOpen"`) with
      `:origin-conversation-id="currentChat.id"` and `:initial-contact="initialContact"`, and
      `@close`/`@created` handlers that set `isCreateModalOpen` back to `false` (depends on T002, T004)
- [x] T006 [US1] In `routes/dashboard/conversation/ContactOpportunities.vue`, add a `watch` on
      `() => currentChat.value.id` that sets `isCreateModalOpen.value = false` whenever it changes,
      so the flow closes automatically on conversation switch (FR-010) (depends on T004)
- [x] T007 [P] [US1] Add an `ADD_OPPORTUNITY` key (e.g. `"Add opportunity"`) under
      `CONVERSATION_SIDEBAR.PREVIOUS_OPPORTUNITIES` in
      `i18n/locale/en/conversation.json`
- [x] T008 [P] [US1] Add the mirrored `ADD_OPPORTUNITY` key (pt-BR translation) under
      `CONVERSATION_SIDEBAR.PREVIOUS_OPPORTUNITIES` in
      `i18n/locale/pt_BR/conversation.json`

**Checkpoint**: User Story 1 is fully functional and independently testable — an agent can create
an opportunity from the open conversation's Contact Panel.

---

## Phase 4: User Story 2 - Prevent duplicate opportunities on the same conversation (Priority: P2)

**Goal**: The "Add opportunity" action is disabled once the current conversation already has a
linked opportunity, and the contact can never be changed once fixed by the conversation-first flow.

**Independent Test**: Open a conversation whose contact already has an opportunity linked to it,
and separately, launch the creation flow from a conversation and attempt to change the contact
(see `quickstart.md` Scenario 2).

### Implementation for User Story 2

- [x] T009 [US2] In `routes/dashboard/conversation/ContactOpportunities.vue`, bind `:disabled` on
      the "Add opportunity" button to
      `opportunities.value.some(o => o.origin_conversation_id === currentChat.value.id)`
      (depends on T004)
- [x] T010 [US2] Verify (no code change expected) that
      `components-next/Opportunities/KanbanBoard.vue` and
      `routes/dashboard/opportunities/components/OpportunitiesViewBar.vue` continue to render
      `OpportunityCreateModal` without `initial-contact`, preserving unchanged
      search-and-select behavior (contract: `contracts/component-interfaces.md`)

**Checkpoint**: User Stories 1 and 2 both work independently — the guardrail is enforced in the UI.

---

## Phase 5: User Story 3 - Find the current conversation's opportunity at a glance (Priority: P3)

**Goal**: The opportunity linked to the current conversation is shown first and visually
distinguished in the Contact Panel's list, and newly created opportunities appear there
immediately without a manual refresh.

**Independent Test**: Open a conversation whose contact has multiple opportunities, including one
linked to the current conversation, and confirm it appears first and is visually distinguished;
then create a new opportunity from that conversation and confirm it appears at the top immediately
(see `quickstart.md` Scenario 3).

### Implementation for User Story 3

- [x] T011 [P] [US3] Add a `PREPEND_ID_TO_CONTACT(state, { contactId, opportunityId })` mutation to
      `store/modules/opportunities/mutations.js`, mirroring `PREPEND_ID_TO_STAGE`, no-op when
      `state.idsByContact[contactId]` is `undefined` (contract: `data-model.md`)
- [x] T012 [US3] In the `create` action in `store/modules/opportunities/actions.js`, commit
      `PREPEND_ID_TO_CONTACT` with `{ contactId: payload.contact_id, opportunityId: payload.id }`
      alongside the existing `ADD_OPPORTUNITY`/`PREPEND_ID_TO_STAGE` commits (depends on T011)
- [x] T013 [P] [US3] Add an `isCurrentConversation` boolean prop (default `false`) to
      `components-next/Opportunities/ContactOpportunityCard.vue`; when `true`, swap the card's
      bottom divider border to the existing accent color token `border-n-brand` instead of
      `border-n-slate-3`
- [x] T014 [US3] In `routes/dashboard/conversation/ContactOpportunities.vue`, add a computed that
      partitions `cardsForContact(contactId)` results by
      `o.origin_conversation_id === currentChat.value.id` (match first, rest in existing order),
      use it in place of the raw list, and pass `:is-current-conversation="true"` only to the
      matching card (depends on T003, T013)

**Checkpoint**: All three user stories are independently functional — the full feature works
end-to-end.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T015 [P] Run `docker compose exec vite pnpm eslint` on all touched files
      (`ContactOpportunities.vue`, `ContactOpportunityCard.vue`, `OpportunityCreateModal.vue`,
      `store/modules/opportunities/{actions.js,mutations.js}`, both i18n files) and fix violations
- [x] T016 [P] Run `docker compose exec vite pnpm test` and confirm existing specs for the touched
      components/store module still pass
- [x] T017 Execute all four `quickstart.md` scenarios manually against the running dev stack

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS User Story 1 (T005) and User Story 2 (T009, T010)
- **User Story 1 (Phase 3)**: Depends on Foundational (T002) for T005; otherwise independent
- **User Story 2 (Phase 4)**: Depends on User Story 1's button existing (T004); Foundational (T002) for the locked-contact guarantee it verifies
- **User Story 3 (Phase 5)**: Depends on User Story 1's `currentChat` wiring (T003); independent of User Story 2
- **Polish (Phase 6)**: Depends on all desired user stories being complete

### Within Each User Story

- T003 → T004 → T005/T006 (same file, sequential edits to `ContactOpportunities.vue`)
- T007/T008 (i18n) are independent of T003–T006 and of each other
- T009 depends on T004 (the button must exist before it can be disabled)
- T011 → T012 (mutation before the action that commits it)
- T013 is independent of T011/T012 (different file)
- T014 depends on T003 (currentChat) and T013 (the prop it passes)

### Parallel Opportunities

- T007 and T008 (i18n, different files) can run in parallel
- T011 and T013 (different files, no shared dependency) can run in parallel
- T015 and T016 (independent commands) can run in parallel
- User Story 2 and User Story 3 implementation can proceed in parallel once User Story 1's T003/T004 land, since T009 only needs T004 and T014 only needs T003

---

## Parallel Example: User Story 1

```bash
# T003 must land first (adds the getters/computed T004 relies on), then:
Task: "Add ADD_OPPORTUNITY key to i18n/locale/en/conversation.json"
Task: "Add ADD_OPPORTUNITY key (pt-BR) to i18n/locale/pt_BR/conversation.json"
```

## Parallel Example: User Story 3

```bash
Task: "Add PREPEND_ID_TO_CONTACT mutation in store/modules/opportunities/mutations.js"
Task: "Add isCurrentConversation prop to components-next/Opportunities/ContactOpportunityCard.vue"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (T002 — blocks the modal pre-fill T005 needs)
3. Complete Phase 3: User Story 1 (T003–T008)
4. **STOP and VALIDATE**: Run `quickstart.md` Scenario 1 independently
5. Demo if ready — this alone closes the core gap (no entry point to create from a conversation)

### Incremental Delivery

1. Setup + Foundational → foundation ready
2. User Story 1 → validate Scenario 1 → MVP demo
3. User Story 2 → validate Scenario 2 → guardrail confirmed
4. User Story 3 → validate Scenarios 3 and 4 → full feature complete
5. Polish (T015–T017) → lint/test/full quickstart pass

---

## Notes

- [P] tasks touch different files with no unmet dependency
- [Story] label maps each task to its user story for traceability
- All five touched files are existing files (no new components/routes/store modules) — every task
  is an edit, not a creation, per `plan.md`'s Constitution Check (Smallest Production-Ready Change)
- Commit after each task or logical group, per repo convention (`docker compose exec vite git
  commit -m "..."`, see `CLAUDE.md`)
- Stop at any checkpoint to validate a story independently before moving to the next
