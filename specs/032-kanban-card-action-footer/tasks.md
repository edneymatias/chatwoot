---

description: "Task list for Kanban Card Action Footer"
---

# Tasks: Kanban Card Action Footer

**Input**: Design documents from `/specs/032-kanban-card-action-footer/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md (N/A), quickstart.md

**Tests**: Not explicitly requested in the feature specification — no automated test tasks are
included, per project convention (avoid writing specs unless explicitly asked). Validation is
performed via the manual scenarios in `quickstart.md`.

**Organization**: Tasks are grouped by user story from `spec.md` (US1 = P1, US2 = P2). Because
this feature is a single-component template/markup change, most tasks touch the same file
(`KanbanCard.vue`) and are therefore sequential rather than parallel.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2)
- Include exact file paths in descriptions

## Path Conventions

Single Vue component inside the existing frontend tree:
`app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`

---

## Phase 1: Setup

**Purpose**: Confirm the current baseline before restructuring the template

- [X] T001 [P] Re-confirm (quick sanity check, not new investigation — this was already verified
      during `/speckit-plan`'s Constitution Check) that no other component reuses the current
      absolute-positioned "Quick Actions Overlay" markup pattern from
      `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`
      (`grep -rn "Quick Actions Overlay" app/javascript`), so the restructuring is safely scoped
      to this one file

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared logic both user stories depend on — the single derived flag that gates the
divider + footer row

**⚠️ CRITICAL**: Must complete before either user story phase

- [X] T002 Add a `hasActions` computed property in the `<script setup>` block of
      `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`, deriving from the
      three existing per-button conditions (`!opportunity.origin_conversation_id`,
      `opportunity.status !== 'open'`, `opportunity.status === 'open'`) per the Phase 0 decision
      in `research.md` ("Conditional rendering of footer + divider")

**Checkpoint**: `hasActions` is available for both user story phases below

---

## Phase 3: User Story 1 - Action buttons appear in a dedicated footer row (Priority: P1) 🎯 MVP

**Goal**: When an opportunity card has at least one available action button, render those
buttons inside a footer row separated from the card's content by a subtle horizontal divider,
right-to-left aligned as today.

**Independent Test**: Hover an opportunity card that has at least one available action (start
conversation / reopen / complete fields) and verify a divider + footer row render with no visual
overlap on card content, per `quickstart.md` Scenarios 1–3.

### Implementation for User Story 1

- [X] T003 [US1] In `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`,
      replace the `absolute bottom-2 right-2 ... opacity-0 group-hover:opacity-100` "Quick
      Actions Overlay" wrapper with a normal-flow footer `<div>` gated by `v-if="hasActions"`,
      using `border-t border-n-slate-3` for the subtle divider and
      `flex items-center justify-end gap-1 opacity-0 group-hover:opacity-100 transition-opacity`
      for the button row, per the Phase 0 decisions in `research.md` ("Divider styling" and
      "Layout mechanics")
- [X] T004 [US1] Within the new footer row in
      `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`, confirm the three
      existing buttons (`StartOpportunityConversationButton`, reopen `<button>`, complete-fields/
      edit `<button>`) keep their current DOM order and `v-if`/`@click.stop` conditions unchanged,
      so right-to-left visual order and click behavior match today's overlay exactly (FR-004,
      FR-005)
- [X] T005 [US1] Manually validate `quickstart.md` Scenarios 1–3 (start-conversation, reopen,
      complete-fields, including the two-button case) against the running dev server
      (`docker compose up -d`) at `http://localhost:3000` → Opportunities → Kanban board

**Checkpoint**: User Story 1 is fully functional — cards with actions show a divider + footer row

---

## Phase 4: User Story 2 - No footer space is reserved when a card has no actions (Priority: P2)

**Goal**: Cards with zero available action buttons keep their current compact height, with no
divider or empty footer rendered.

**Independent Test**: Hover/inspect an opportunity card for which no action condition applies and
verify no divider or footer row renders and card height is unchanged, per `quickstart.md`
Scenario 4.

### Implementation for User Story 2

- [X] T006 [US2] Manually validate `quickstart.md` Scenario 4 (open opportunity with
      `origin_conversation_id` set and all required stage fields filled): confirm no divider/
      footer row renders on the card produced by `hasActions` (T002) evaluating to `false` in
      `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`, and that card
      height matches the pre-change baseline
- [X] T007 [US2] Manually validate the `quickstart.md` "Manual regression check": confirm the
      footer row's hover opacity transition timing on
      `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue` is unchanged from
      the pre-change overlay behavior (FR-006)

**Checkpoint**: Both user stories are independently verified — action cards show the footer,
no-action cards stay compact

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Final quality gates across the whole change

- [X] T008 [P] Run
      `docker compose exec vite pnpm eslint app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`
      and fix any reported issues
- [X] T009 [P] Run `docker compose exec vite pnpm test` to confirm no existing suite regresses
- [X] T010 Run the full `quickstart.md` validation guide end-to-end (all 4 scenarios + regression
      check) as a final pass before marking the feature done

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — BLOCKS both user stories
- **User Story 1 (Phase 3)**: Depends on Foundational (T002) — delivers the MVP
- **User Story 2 (Phase 4)**: Depends on Foundational (T002); in practice shares the same template
  edit as US1 (T003), so it is validated once US1's implementation lands, but is listed
  separately because it has its own independent acceptance criteria (no footer when no actions)
- **Polish (Phase 5)**: Depends on both user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) — no dependency on US2
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) — validates the negative case of
  the same `hasActions`/template change introduced in US1's implementation task (T003); no new
  markup is needed, only validation

### Within Each User Story

- T003 (template restructure) before T004 (button order/condition check) before T005 (manual
  validation)
- T006/T007 (US2 validation) can only be meaningfully run once T003 exists

### Parallel Opportunities

- T001 (Setup) can run in parallel with nothing else pending (it's the only Setup task)
- T008 and T009 (Polish) can run in parallel with each other (different tool invocations, no
  shared file edits)
- T003 and T004 touch the same file/section and are NOT parallel; do them in order

---

## Parallel Example: Polish Phase

```bash
# Launch both polish checks together:
Task: "Run pnpm eslint on KanbanCard.vue"
Task: "Run pnpm test for the frontend suite"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational (T002 — CRITICAL, blocks both stories)
3. Complete Phase 3: User Story 1 (T003–T005)
4. **STOP and VALIDATE**: Run `quickstart.md` Scenarios 1–3
5. This alone delivers the visible product change (divider + footer row for cards with actions)

### Incremental Delivery

1. Setup + Foundational → `hasActions` flag ready
2. User Story 1 → divider + footer row render correctly → validate (MVP)
3. User Story 2 → confirm the negative case (no actions → no footer) → validate
4. Polish → lint, test suite, full quickstart pass

---

## Notes

- This is a single-file, single-component change — most tasks are sequential rather than
  parallel because T002/T003/T004 all edit
  `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`.
- No new files, models, services, or contracts are introduced (see `data-model.md`, marked N/A).
- Commit after the Foundational + User Story 1 tasks land together (they form one coherent
  template edit), then again after Polish.

---

## Phase 6: Convergence

- [X] T011 Fix `hasActions` computed property in `KanbanCard.vue` to correctly evaluate to false for cards with no actionable items (e.g., open opportunities that already have `origin_conversation_id` set and have all required stage fields filled). Currently it is a tautology (`status !== 'open' || status === 'open'`). per US2/AC1 (contradicts)
