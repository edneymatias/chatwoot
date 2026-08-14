# Tasks: Funnel Stage Rich Description & Kanban Info Panel

**Input**: Design documents from `/specs/034-funnel-stage-description-editor/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[data-model.md](./data-model.md), [contracts/pipeline_stages_api.md](./contracts/pipeline_stages_api.md),
[quickstart.md](./quickstart.md)

**Tests**: No dedicated automated test tasks are included — the spec does not request tests, and
project convention (`CLAUDE.md`) is to avoid writing specs unless explicitly asked. Each user
story instead includes a manual validation task against `quickstart.md`, and the Polish phase runs
the *existing* RSpec/Vitest suites to guard against regressions.

**Organization**: Tasks are grouped by user story (US1/US2/US3, matching spec.md priorities P1/P2/P3)
to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- File paths are absolute to the repository root

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Bring in the new, isolated rich-text editor dependency (see research.md R3) before any
component that uses it is built.

- [X] T001 [P] Add `@tiptap/vue-3`, `@tiptap/starter-kit`, `@tiptap/extension-underline` as
  frontend dependencies: `docker compose exec vite pnpm add @tiptap/vue-3 @tiptap/starter-kit
  @tiptap/extension-underline`, updating `package.json` and `pnpm-lock.yaml`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Add the missing database column that is the root cause of the persistence bug
(research.md R1/R5). Every user story's acceptance criteria depend on this column existing.

**⚠️ CRITICAL**: No user story work can be validated until this phase is complete.

- [X] T002 Create additive migration `db/migrate/<timestamp>_add_description_to_ichatr_pipeline_stages.rb`
  with `add_column :ichatr_pipeline_stages, :description, :text`, following the exact pattern of
  the existing `db/migrate/21260804135223_add_stale_after_days_to_ichatr_pipeline_stages.rb`; run
  `docker compose exec rails bundle exec rails db:migrate` and confirm `db/schema.rb`'s
  `create_table "ichatr_pipeline_stages"` block now includes `t.text "description"`.

**Checkpoint**: Foundation ready — the `description` column exists and the already-correct
frontend (`EditPipelineStage.vue`) and backend (`pipeline_stages_controller.rb`,
`pipeline_stage_params`) can now actually persist and return it.

---

## Phase 3: User Story 1 - Stage description is actually saved (Priority: P1) 🎯 MVP

**Goal**: A saved stage description is present when the edit form is reopened.

**Independent Test**: Edit a stage, type a description, save, reopen the edit form, confirm the
same text is present; clear it and save, confirm it stays empty on reload.

### Implementation for User Story 1

- [X] T003 [US1] Manually validate the persistence fix per
  `specs/034-funnel-stage-description-editor/quickstart.md` Section 1: edit a stage via
  `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/EditPipelineStage.vue`, save
  a description, reopen the form, confirm it persisted (FR-001, FR-002); clear it and resave,
  confirm it stays empty (FR-003). No code changes are expected here beyond T002 — the frontend
  payload and backend `pipeline_stage_params` already round-trip `description` correctly (see
  research.md R1/R5); this task exists to confirm that and catch any surprise.

**Checkpoint**: User Story 1 is fully functional and testable independently — the core data-loss
bug is fixed.

---

## Phase 4: User Story 2 - Simple rich-text formatting for the description (Priority: P2)

**Goal**: The stage edit form supports bold/italic/strikethrough/underline/ordered+bulleted lists,
and that formatting round-trips through save/reload.

**Independent Test**: Apply each formatting option in the edit form, save, reopen the form, and
confirm both the text and its formatting are preserved.

**Depends on**: Phase 3 (persistence must work before formatting is worth testing).

### Implementation for User Story 2

- [X] T004 [P] [US2] Create
  `app/javascript/dashboard/components-next/Opportunities/StageDescriptionEditor.vue`: a
  Tiptap-based (`@tiptap/vue-3` + `StarterKit` + `Underline`) rich-text input with a small toolbar
  (bold, italic, strikethrough, underline, ordered list, bulleted list) using `fluent-icon` or
  standard Unocss fluent icon classes (e.g. `i-fluent-text-bold-24-regular`, `i-fluent-text-italic-24-regular`,
  `i-fluent-text-strikethrough-24-regular`, `i-fluent-text-underline-24-regular`, `i-fluent-text-number-list-ltr-24-regular`,
  `i-fluent-text-bullet-list-24-regular`) for the toolbar buttons (for visual consistency with the rest
  of the dashboard, per Constitution Principle III), Composition API `<script setup>`, Tailwind
  utility classes only, emitting an HTML string via `v-model` (`modelValue`/`update:modelValue`)
  — per research.md R2/R3. Do not import from `WootWriter/Editor.vue`, `WootWriter/FullEditor.vue`,
  or `@chatwoot/prosemirror-schema`.
- [X] T005 [US2] In
  `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/EditPipelineStage.vue`,
  replace the plain `<textarea v-model="description">` with
  `<StageDescriptionEditor v-model="description" />`. Update the `submit()` payload so that a
  structurally-empty editor (Tiptap `isEmpty`, e.g. an untouched/cleared editor serializing as
  `<p></p>`) is sent as `''` rather than that empty markup — per research.md R3a — instead of the
  old plain `description.value.trim()` call, so FR-003's "cleared description persists as empty"
  holds for HTML content too. Depends on T004.
- [X] T006 [P] [US2] Add any new i18n keys needed for the formatting toolbar's button labels/
  tooltips (e.g. under `PIPELINE_STAGES_MGMT.FORM` or a new
  `PIPELINE_STAGES_MGMT.FORM.DESCRIPTION_EDITOR` group) to
  `app/javascript/dashboard/i18n/locale/en/opportunities.json` — no bare strings in the new
  component's template.
- [X] T007 [P] [US2] Mirror the same new i18n keys from T006 into
  `app/javascript/dashboard/i18n/locale/pt_BR/opportunities.json` (pt-BR ships with the Kanban
  module per project i18n convention).
- [X] T008 [US2] Manually validate formatting persistence per
  `specs/034-funnel-stage-description-editor/quickstart.md` Section 2: apply bold, italic,
  strikethrough, underline, an ordered list, and a bulleted list; save; reopen the form; confirm
  all formatting is restored visually, not as raw markup (FR-004, FR-005, FR-012, SC-002).
  Depends on T004, T005.

**Checkpoint**: User Stories 1 AND 2 both work independently — descriptions persist and support
rich formatting.

---

## Phase 5: User Story 3 - Expandable stage info panel on the kanban board (Priority: P3)

**Goal**: A clickable circular info icon in each kanban column header toggles a panel below the
header showing the stage's rendered description, pushing cards down; independent per column; a
friendly empty state when no description exists.

**Independent Test**: Open the kanban board for a stage with a saved description, click its info
icon, confirm the panel appears and renders formatted content; click again to collapse; repeat on a
stage with no description and confirm the guiding empty state.

**Depends on**: Phase 3 (needs real, persisted description data) and benefits from Phase 4 (rich
formatting) but only requires the data to exist — it renders whatever HTML is stored.

### Implementation for User Story 3

- [X] T009 [US3] In
  `app/javascript/dashboard/components-next/Opportunities/KanbanColumn.vue`, add a circular
  information icon/button (`<fluent-icon icon="info" size="16px" ... />` or `i-fluent-info-16-regular` wrapped in a circular button styling) to the left of the `stage.name` title in
  the column header, with a local reactive `isInfoExpanded` ref and a click handler that toggles
  it (FR-006, FR-007, FR-009 — state is naturally per-component-instance/per-column already).
- [X] T010 [US3] In the same file, add an expandable section rendered directly below the column
  header (above the `Draggable` card list) that shows when `isInfoExpanded` is true: render
  `stage.description` with the existing `v-dompurify-html` directive when it is present and
  non-blank (FR-007, FR-012), or a friendly empty-state message guiding the user to the funnel
  stage settings when it is blank (per the resolved Clarifications in
  `specs/034-funnel-stage-description-editor/spec.md`, FR-011). Because T005 normalizes a
  structurally-empty editor to `''` before saving (research.md R3a), a simple blank/whitespace
  check on `stage.description` here is sufficient — no HTML-stripping logic needed. Depends on
  T009.
- [X] T011 [US3] Ensure the panel pushes the card list down rather than overlapping it (it should
  occupy normal flow space above the `Draggable`, not be absolutely positioned), constrain very
  long descriptions to a scrollable max-height rather than growing unboundedly (Edge Cases,
  FR-008), and verify the info icon and expanded panel remain usable without overlapping the
  title or the add-card button at the column's narrow/mobile width (Edge Cases: narrow/mobile
  board layouts). Depends on T010.
- [X] T012 [P] [US3] Add the new empty-state i18n key(s) (e.g.
  `OPPORTUNITIES.BOARD.STAGE_INFO.EMPTY_STATE`) with the friendly, guiding copy agreed in
  Clarifications to `app/javascript/dashboard/i18n/locale/en/opportunities.json`.
- [X] T013 [P] [US3] Mirror the same new i18n key(s) from T012 into
  `app/javascript/dashboard/i18n/locale/pt_BR/opportunities.json`.
- [X] T014 [US3] Manually validate the kanban info panel per
  `specs/034-funnel-stage-description-editor/quickstart.md` Section 3: toggle the panel open/closed
  on a stage with a description (confirms rendering + card push-down + collapse, FR-007–FR-010),
  toggle it on a stage without one (confirms empty state, FR-011), expand two different columns'
  panels simultaneously to confirm independence (FR-009), and check the icon/panel at a narrow
  column width (or a small viewport) to confirm no overlap with the title or add-card button
  (Edge Cases: narrow/mobile board layouts). Depends on T009, T010, T011.

**Checkpoint**: All three user stories are independently functional — the bug is fixed, formatting
works, and the board surfaces stage guidance in place.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Regression-check the changed areas using the project's existing tooling/tests (no new
specs added, per project convention).

- [X] T015 [P] Run `docker compose exec vite pnpm eslint:fix` and
  `docker compose exec rails bundle exec rubocop -a` and resolve any offenses in the files touched
  by T002, T004, T005, T009, T010, T011.
- [X] T016 Run the existing backend suites for the touched areas:
  `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec
  spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb spec/models/pipeline_stage_spec.rb`
  and confirm no regressions.
- [X] T017 Run `docker compose exec vite pnpm test` and confirm no regressions in existing frontend
  suites touching `pipelineStages`/`Opportunities`.
- [X] T018 Walk through `specs/034-funnel-stage-description-editor/quickstart.md` end-to-end in a
  running dev environment as a final sanity pass across all three user stories together.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately.
- **Foundational (Phase 2)**: No dependency on Phase 1's Tiptap install (independent concerns);
  BLOCKS all user story validation (US1–US3 all need the `description` column to exist).
- **User Story 1 (Phase 3)**: Depends on Phase 2 only.
- **User Story 2 (Phase 4)**: Depends on Phase 2 (data) and Phase 1 (Tiptap dependency); builds on
  top of Phase 3 being validated first (formatting is pointless if plain persistence is broken),
  but does not modify any Phase 3 code.
- **User Story 3 (Phase 5)**: Depends on Phase 2 (data); reads whatever `description` HTML is
  already stored, so it can be built in parallel with Phase 4 by a different person, but is best
  validated after Phase 4 so there is real formatted content to look at.
- **Polish (Phase 6)**: Depends on all desired user stories being complete.

### Parallel Opportunities

- T001 (Setup) can run in parallel with T002 (Foundational) — different areas (frontend deps vs.
  DB migration).
- T006/T007 (US2 i18n) and T012/T013 (US3 i18n) can each run in parallel with their sibling
  implementation tasks, and with each other.
- T009 (US3, KanbanColumn icon) can start as soon as Phase 2 is done, in parallel with all of
  Phase 4, since it doesn't depend on `StageDescriptionEditor.vue`.

---

## Parallel Example: Phase 4 (User Story 2)

```bash
# Once Phase 2 and T001 are done, these can run together:
Task: "Create StageDescriptionEditor.vue in app/javascript/dashboard/components-next/Opportunities/StageDescriptionEditor.vue"
Task: "Add new i18n keys to app/javascript/dashboard/i18n/locale/en/opportunities.json"
Task: "Mirror new i18n keys to app/javascript/dashboard/i18n/locale/pt_BR/opportunities.json"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (Setup) and Phase 2 (Foundational — the migration).
2. Complete Phase 3 (US1) — validate the persistence fix.
3. **STOP and VALIDATE**: the data-loss bug is fixed; this alone is shippable.

### Incremental Delivery

1. Setup + Foundational → migration applied, dependency installed.
2. Add US1 → validate → ship the bug fix (MVP).
3. Add US2 → validate → ship rich-text formatting.
4. Add US3 → validate → ship the kanban info panel.
5. Polish → regression-check everything together.

---

## Notes

- [P] tasks touch different files and have no unmet dependencies.
- Each user story phase is independently checkpointable per its Independent Test in spec.md.
- No automated test tasks were added (project convention); Phase 6 relies on existing suites plus
  manual `quickstart.md` walkthroughs embedded in each story phase.
- Commit after each task or logical group, per repo convention (`docker compose exec vite git
  commit ...`), only once the user has locally validated the change (per `CLAUDE.md`'s workflow
  constraint on this fork).
