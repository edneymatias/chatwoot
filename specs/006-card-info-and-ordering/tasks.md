---

description: "Task list for Card Info Enrichment & Lane Ordering"

---

# Tasks: Card Info Enrichment & Lane Ordering

**Input**: Design documents from `/specs/006-card-info-and-ordering/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Not requested. Per project convention (`CLAUDE.md`: "avoid writing specs unless explicitly asked"), no new spec files are added. Existing specs are only touched if this change breaks their current expectations (see Polish phase).

**Organization**: Tasks are grouped by user story (P1/P1/P3 per spec.md) so each can be delivered and verified independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Maps task to US1/US2/US3 from spec.md
- File paths are exact and reference this fork's actual layout

## Path Conventions

Fork-specific layout confirmed in plan.md / research.md:
- Backend: `custom/app/models/opportunity.rb`, `custom/app/controllers/api/v1/accounts/opportunities_controller.rb`
- Frontend: `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`
- Reused, unmodified: `app/javascript/dashboard/components-next/avatar/Avatar.vue`, `app/javascript/shared/helpers/timeHelper.js`, `app/models/concerns/avatarable.rb`

---

## Phase 1: Setup

No new dependencies, scaffolding, or project structure changes are needed — this feature extends three existing files in place. Skip directly to Foundational.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The backend payload shape change that both US1 (contact identity) and US3 (creation date) depend on. Both additions land in the same `as_json` method, so they're grouped as one blocking task rather than split and risking edit conflicts across stories.

**⚠️ CRITICAL**: US1 and US3 cannot be implemented until this is complete. US2 has no dependency on this phase (different file, different concern) and can proceed independently at any time.

- [X] T001 Extend `Opportunity#as_json` in `custom/app/models/opportunity.rb` to merge, on top of the existing `origin_conversation_display_id` merge: `created_at: created_at.to_i` (epoch seconds, overriding the default ISO8601 string per research.md Decision 1); `contact: { id, name, email, avatar_url }` or `nil` when `contact_id` is absent; `assignee: { id, name, avatar_url }` or `nil` when unassigned — sourcing `avatar_url` from the existing `Avatarable#avatar_url` on `Contact`/`User` (per research.md Decision 2 and data-model.md field provenance table). No new serializer class.

**Checkpoint**: `Opportunity#as_json` now returns the full enriched shape described in data-model.md — US1 and US3 frontend work can begin.

---

## Phase 3: User Story 1 - Agent identifies a card's contact at a glance (Priority: P1) 🎯 MVP

**Goal**: Every card with a linked contact shows that contact's avatar and name without opening the card.

**Independent Test**: Load the board and confirm every card with a linked contact shows that contact's avatar (or initials fallback) next to their name (quickstart.md §2).

### Implementation for User Story 1

- [X] T002 [US1] In `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`, import and render the existing `Avatar.vue` (`components-next/avatar/Avatar.vue`) next to the contact name, only when `opportunity.contact` is present, using `:name="opportunity.contact.name"`, `:src="opportunity.contact.avatar_url"`, `:size="24"` (matching the established convention used by `ConversationCard.vue`/`CardAvatar.vue`). Leave assignee rendering as plain name-only text (unchanged), per spec Assumptions — no assignee avatar this phase. Depends on T001 (needs `contact.avatar_url` in the API response).

**Checkpoint**: User Story 1 is fully functional and independently testable — contact avatars render on the board.

---

## Phase 4: User Story 2 - Agent trusts the board's newest-first ordering across reloads (Priority: P1)

**Goal**: Cards within each lane are ordered newest-created-first on every board load/reload, independent of client-side drag state.

**Independent Test**: Create several opportunities in a lane, reload the board from scratch, and confirm they still appear newest-first by creation time (quickstart.md §1, §3).

### Implementation for User Story 2

- [X] T003 [P] [US2] Add `.order(created_at: :desc)` to the base relation in `OpportunitiesController#index` (`custom/app/controllers/api/v1/accounts/opportunities_controller.rb`), applied before the existing `.where(pipeline_stage_id: ...)` / `.page(...)` chaining. No Vuex store changes — `MOVE_CARD_OPTIMISTIC` only affects in-memory drag state, and a reload always re-issues `#index` against the ordered query (research.md Decision 3). Independent of T001/T002 — different file, can run in parallel with Phase 2/3. This same `ORDER BY created_at` also satisfies FR-004 (moving a card to another stage never changes relative creation-time ordering, since `created_at` is untouched by a stage move) — no separate task needed.

**Checkpoint**: User Stories 1 and 2 both work independently. Ordering survives reload and stage moves.

---

## Phase 5: User Story 3 - Agent sees how recently an opportunity was created (Priority: P3)

**Goal**: Every card shows a human-readable, relative creation date.

**Independent Test**: Load the board and confirm every card shows a human-readable creation date/time (quickstart.md §2).

### Implementation for User Story 3

- [X] T004 [US3] In `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`, import `dynamicTime`/`shortTimestamp` from `shared/helpers/timeHelper` and render `shortTimestamp(dynamicTime(opportunity.created_at))` on the card, matching the pattern already used in `ConversationCard.vue` (`shortTimestamp(dynamicTime(timestamp))`). No new "open conversation" element is added (FR-007) — whole-card click behavior is unchanged. Depends on T001 (needs `created_at` as epoch seconds); touches the same file as T002, so sequence after it to avoid merge conflicts.

**Checkpoint**: All three user stories are independently functional — contact avatars, stable ordering, and relative creation dates all render correctly.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T005 [P] Run `docker compose exec rails bundle exec rubocop -a custom/app/models/opportunity.rb custom/app/controllers/api/v1/accounts/opportunities_controller.rb` and fix any offenses.
- [X] T006 [P] Run `docker compose exec vite pnpm eslint app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue` and fix any offenses.
- [X] T007 Run existing `spec/models/opportunity_spec.rb` and `spec/requests/api/v1/accounts/opportunities_controller_spec.rb` (`docker compose exec rails bundle exec rspec ...`). Per project convention, do not add new spec files — only adjust existing expectations if they assert on the previous `as_json` shape (ISO8601 `created_at`, no `contact`/`assignee` keys) or the previous unordered `#index` result, since T001/T003 change that observable behavior.
- [X] T008 Execute the full manual validation walkthrough in `quickstart.md` (API shape/ordering via curl, UI rendering of avatar/date, ordering stability across drag + reload).
- [X] T009 Verify FR-007 (no new "open conversation" element added by T002/T004): on the updated `KanbanCard.vue`, confirm clicking anywhere on the card body (including over the new avatar and date) still opens the conversation drawer exactly as before, and that no new clickable link/button was introduced (quickstart.md §2, step 5).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: None — no tasks.
- **Foundational (Phase 2)**: No dependencies — BLOCKS User Story 1 (Phase 3) and User Story 3 (Phase 5) only.
- **User Story 2 (Phase 4)**: No dependency on Foundational — can start immediately, in parallel with Phase 2/3/5.
- **User Story 1 (Phase 3)** and **User Story 3 (Phase 5)**: Both depend on Phase 2 (T001) and both edit `KanbanCard.vue`, so T004 should land after T002 to avoid a merge conflict in the same file.
- **Polish (Phase 6)**: Depends on all desired user stories being complete.

### Parallel Opportunities

- T003 (US2, controller) can run in parallel with T001 (Foundational) and T002/T004 (US1/US3, frontend) — entirely different file and concern.
- T005 and T006 (lint) can run in parallel with each other once their respective source changes land.

---

## Parallel Example

```bash
# Once the feature starts, these two tracks are independent and can run in parallel:
Task: "T001 Extend Opportunity#as_json in custom/app/models/opportunity.rb"
Task: "T003 Add .order(created_at: :desc) to OpportunitiesController#index"

# T002 and T004 both touch KanbanCard.vue and both depend on T001 — run sequentially, not in parallel.
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational (T001).
2. Complete Phase 3: User Story 1 (T002).
3. **STOP and VALIDATE**: Confirm contact avatars render per quickstart.md §2.
4. Ship — this alone resolves the highest-priority gap (agents can't identify a card's contact today).

### Incremental Delivery

1. Foundational (T001) → contact/assignee/created_at now in the API response.
2. Add User Story 1 (T002) → contact avatars render → validate → ship.
3. Add User Story 2 (T003, independent of the above) → ordering is stable across reload → validate → ship.
4. Add User Story 3 (T004) → relative creation dates render → validate → ship.
5. Polish (T005-T008) → lint, existing-spec regression check, full quickstart pass.

### Notes

- Only 3 production files are touched in total (`opportunity.rb`, `opportunities_controller.rb`, `KanbanCard.vue`); no new files, no schema changes, no new serializer class — matches the "smallest production-ready change" scope fixed in plan.md.
- T002 and T004 are the only same-file overlap; every other task pair is safely parallelizable.

---

## Phase 7: Convergence

- [X] T010 Review/justify manual creation UI per none (unrequested)
- [X] T011 Review/justify default title format change per none (unrequested)
