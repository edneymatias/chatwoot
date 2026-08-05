# Tasks: Graphical Funnel Chart

**Input**: Design documents from `/specs/017-graphical-funnel-chart/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Not explicitly requested in the feature spec, so no dedicated test-writing tasks are
generated; validation is via the manual `quickstart.md` scenarios in the Polish phase (per
project convention: avoid writing specs unless explicitly asked).

**Organization**: Tasks are grouped by user story to enable independent implementation and
testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- File paths are relative to the repo root

## Path Conventions
- Frontend: `app/javascript/shared/components/charts/`, `app/javascript/dashboard/routes/dashboard/settings/reports/`
- Backend (fork-specific overlay, per Constitution Principle I — never `app/`/`enterprise/`): `custom/app/services/reports/`

---

## Phase 1: Setup

- [X] T001 Ensure dev stack is up and seed an account with pipeline stages/opportunities per
      `quickstart.md` Prerequisites (`docker compose up -d`; seed data with at least one stage
      lacking `accent_color` to exercise the fallback-color path later) — environment check only,
      no file changes

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Backend data and frontend component scaffold that every user story builds on top of

- [X] T002 [P] Add `counts` (raw per-stage opportunity count, `Array<Integer>`) to
      `Reports::OpportunityFunnelBuilder#conversion_funnel`'s return hash in
      `custom/app/services/reports/opportunity_funnel_builder.rb`, derived from the existing
      `reached` hash built by `max_stage_positions_reached` (FR-008; see `data-model.md` and
      `research.md` Decision 2 for the exact computation — no new query)
- [X] T003 [P] Create the `FunnelChart.vue` skeleton in
      `app/javascript/shared/components/charts/FunnelChart.vue` with `<script setup>`, the
      `points`/`valueLabel` props per `contracts/funnel-chart-component.md`, and an empty SVG root
      (no band rendering yet)

**Checkpoint**: Backend serves `counts`; a (visually empty) `FunnelChart.vue` component exists to build on.

---

## Phase 3: User Story 1 - View pipeline drop-off as a proportional funnel (Priority: P1) 🎯 MVP

**Goal**: Replace the bar chart with a tapering funnel where band width is proportional to each
stage's percentage, with an inline label, badge percentage, and count per band.

**Independent Test**: Open the Opportunity Funnel Report; confirm the Conversion Funnel section
renders continuous, curved-edge tapering bands (not bars) whose relative widths make the steepest
drop-off stage visually obvious, each labeled with stage name, percentage, and count.

- [X] T004 [US1] Implement per-band curved-path (cubic Bézier taper) geometry computation in
      `app/javascript/shared/components/charts/FunnelChart.vue`, deriving each band's start/end
      width from `percentage` relative to the first point's `percentage` (depends on T003)
- [X] T005 [US1] Render one SVG `<path>`/group per `points` entry, in order, using the computed
      geometry and binding `fill` to `point.color`, in
      `app/javascript/shared/components/charts/FunnelChart.vue` (depends on T004)
- [X] T006 [US1] Render each band's inline label (stage name, badge-styled percentage, count) when
      space allows, in `app/javascript/shared/components/charts/FunnelChart.vue` (depends on T005)
- [X] T007 [US1] Handle the zero-point (empty container, no error) and single-point (single band,
      no error) edge cases in `app/javascript/shared/components/charts/FunnelChart.vue` (depends
      on T005)
- [X] T008 [US1] Clamp `percentage` to `[0, 100]` defensively before computing band geometry in
      `app/javascript/shared/components/charts/FunnelChart.vue` (depends on T004)
- [X] T009 [US1] Add a `funnelPoints` computed in
      `app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityFunnelReport.vue`
      mapping `conversion_funnel.labels/count_data/counts` to `{ label, percentage, count, color }`
      per `contracts/conversion-funnel-data-contract.md` (color: use the existing
      `DEFAULT_BAR_COLOR` for every point for now — per-stage color is refined in US3) (depends on
      T002)
- [X] T010 [US1] In the Conversion Funnel section of
      `app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityFunnelReport.vue`,
      replace `<BarChart :collection="conversionFunnelData" :chart-options="percentChartOptions">`
      with `<FunnelChart :points="funnelPoints">`, and remove the now-unused
      `conversionFunnelData` computed and `percentChartOptions` (verify no other chart on the page
      references them before removing) (depends on T006, T009)

**Checkpoint**: User Story 1 is fully functional — the funnel shape renders with proportional,
labeled bands (uniform placeholder color until US3).

---

## Phase 4: User Story 2 - Read exact stage detail via hover (Priority: P2)

**Goal**: Hovering any band reveals a tooltip with that stage's full detail, so narrow/small bands
remain fully readable.

**Independent Test**: Hover over a band too narrow for inline text (and a wide one) and confirm a
tooltip appears showing label, count, and percentage; confirm it disappears on mouse-leave.

- [X] T011 [US2] Add `hoveredIndex` local state with `@mouseenter`/`@mouseleave` handlers per band
      in `app/javascript/shared/components/charts/FunnelChart.vue` (depends on T005)
- [X] T012 [US2] Render a Tailwind-styled tooltip (label, count, percentage) positioned near the
      hovered band, shown only while `hoveredIndex` matches, in
      `app/javascript/shared/components/charts/FunnelChart.vue` (depends on T011)

**Checkpoint**: User Stories 1 and 2 both work independently — funnel renders, and hover reveals
full detail on any band regardless of size.

---

## Phase 5: User Story 3 - Recognize stages by consistent color (Priority: P3)

**Goal**: Each band uses that pipeline stage's own accent color (matching the kanban board),
falling back to the existing default color when a stage has none set.

**Independent Test**: Compare each band's color against its stage's kanban board color; confirm a
stage with no accent color renders in the same fallback color the bar chart already used.

- [X] T013 [US3] Extend the `funnelPoints` computed in
      `app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityFunnelReport.vue` to
      source each point's `color` from the existing `stageColorByName` lookup, falling back to
      `DEFAULT_BAR_COLOR` (FR-004, replacing the uniform placeholder from T009) (depends on T009)

**Checkpoint**: All three user stories complete — proportional funnel, hover detail, and per-stage
color are all in place.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T014 [P] Run `docker compose exec vite pnpm eslint` and fix any lint issues in the touched
      frontend files
- [X] T015 [P] Run `docker compose exec rails bundle exec rubocop -a` on
      `custom/app/services/reports/opportunity_funnel_builder.rb`
- [X] T016 Execute `quickstart.md`'s Backend, Component-level, and Page-level validation steps
      end-to-end; confirm Success Criteria SC-001–SC-004

---

## Dependencies & Execution Order

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 completion; T002 and T003 are independent of each
  other (different stacks/files) and can run in parallel
- **Phase 3 (US1)**: Depends on Phase 2 (T002, T003) completion; blocks nothing else, but Phase 4
  and 5 build on the same `FunnelChart.vue` file T004-T010 produce
- **Phase 4 (US2)**: Depends on T005 (band rendering must exist to attach hover handlers);
  independent of Phase 5
- **Phase 5 (US3)**: Depends on T009 (the `funnelPoints` computed must exist to extend it);
  independent of Phase 4
- **Phase 6 (Polish)**: Depends on all user story phases being complete

### User Story Dependency Summary

- User Story 1 (P1): Depends only on Foundational — this is the MVP
- User Story 2 (P2): Depends on Foundational + US1's band rendering (T005); does not depend on US3
- User Story 3 (P3): Depends on Foundational + US1's data mapping (T009); does not depend on US2

## Parallel Execution Examples

**Foundational phase** (after Setup):
```
T002 (backend counts field) and T003 (FunnelChart.vue skeleton) — different files/stacks, run together
```

**Polish phase** (after all stories done):
```
T014 (eslint) and T015 (rubocop) — different toolchains/files, run together
```

Within Phase 3/4/5, most tasks touch the same one or two files sequentially (`FunnelChart.vue`,
`OpportunityFunnelReport.vue`), so they are not marked `[P]` beyond the pairs above.

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (T002, T003)
3. Complete Phase 3: User Story 1 (T004-T010)
4. **STOP and VALIDATE**: Run quickstart.md's Page-level validation steps 1-2 — funnel shape
   renders with proportional, labeled bands
5. Deploy/demo if ready — hover and per-stage color are enhancements, not blockers, for the core
   visual value

### Incremental Delivery

1. Setup + Foundational → backend `counts` field live, component scaffold exists
2. Add User Story 1 → funnel shape replaces bar chart (MVP!)
3. Add User Story 2 → hover tooltips for full detail on any band
4. Add User Story 3 → per-stage accent colors replace the placeholder color
5. Each story adds value without breaking the previous one

## Notes

- No `[P]` tasks within Phase 3 beyond T002/T003 (Foundational) and T014/T015 (Polish) — nearly
  all US1-US5 work sequentially edits the same two files
- No test-writing tasks were generated (not explicitly requested); `quickstart.md` (T016) is the
  validation mechanism
- FR-004 (per-stage accent color) is only fully satisfied once T013 (US3) lands; T009 (MVP)
  ships every band in the uniform placeholder color. If stopping after MVP, note that FR-004 is
  not yet complete.
- SC-001 (steepest drop-off visually obvious within ~5 seconds) has no dedicated automated task;
  it is validated qualitatively as part of T016's Page-level `quickstart.md` walkthrough.
- Commit after each task or logical group
- Stop at any checkpoint to validate independently before continuing
