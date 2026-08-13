# Implementation Plan: Kanban Card Action Footer

**Branch**: `032-kanban-card-action-footer` | **Date**: 2026-08-12 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/032-kanban-card-action-footer/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Move the opportunity Kanban card's action buttons (start conversation / reopen / complete
fields) out of the absolutely-positioned `bottom-2 right-2` overlay in `KanbanCard.vue` and into
a normal-flow footer row, preceded by a subtle top border/divider, rendered only when at least
one action button condition is true. Buttons keep their current right-to-left order and
hover-driven opacity behavior; only their structural placement (flow vs. overlay) changes.

## Technical Context

**Language/Version**: Vue 3 (Composition API, `<script setup>`), JavaScript (ES2022+)

**Primary Dependencies**: Vuex (`opportunities`/`pipelineStages` stores), Vue Router, existing
`StartOpportunityConversationButton.vue`, `fluent-icon` component — all already imported by
`KanbanCard.vue`; no new dependencies

**Storage**: N/A (presentational-only change, no data/model change)

**Testing**: `pnpm test` (Vitest) — no existing spec file for `KanbanCard.vue`; per project
convention, no new spec is added unless explicitly requested

**Target Platform**: Web dashboard (Chatwoot frontend), Kanban board view

**Project Type**: Web application (frontend-only change within the existing monorepo frontend)

**Performance Goals**: N/A — purely a CSS/layout restructuring of an already-rendered component;
no measurable performance target beyond "no layout thrash/jank on hover" (unchanged from today)

**Constraints**: Tailwind utility classes only (no custom/scoped CSS per project conventions);
must not change the conditions under which each action button is shown; must not add height to
cards that have no visible action buttons

**Scale/Scope**: Single component (`KanbanCard.vue`); ~15-25 line template change; no new files,
no backend/API involvement

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Principle I (Upstream Compatibility First)**: N/A trigger — `KanbanCard.vue` lives under
  `components-next/Opportunities/`, a fork-specific Kanban feature with no upstream counterpart,
  so there is no upstream file being diverged from. PASS.
- **Principle II (Smallest Production-Ready Change)**: Change is scoped to the template markup of
  one component; no refactor of unrelated logic, no new abstractions, no new props/emits beyond
  what already exists. PASS.
- **Principle III (Adhere to Established Conventions)**: Uses Tailwind utility classes only
  (e.g. `border-t border-n-slate-3` — matches divider tokens already used elsewhere in this
  component family, per `ContactOpportunityCard.vue`'s `border-b border-n-slate-3`), Composition
  API/`<script setup>` already in place, no template string i18n bypass introduced. PASS.
- **Principle IV (Safe, Reversible Change Management)**: Local, reversible file edit; no
  destructive operations. PASS.
- **Principle V (Dual-Tree Awareness)**: Confirmed no `enterprise/` override exists for
  `KanbanCard.vue` (`grep -rl "KanbanCard" enterprise/` returns nothing). PASS, no action needed.

No violations. Complexity Tracking section is not needed.

## Project Structure

### Documentation (this feature)

```text
specs/032-kanban-card-action-footer/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command) — N/A, no data entities
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command) — N/A, no external interface
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
app/javascript/dashboard/components-next/Opportunities/
├── KanbanCard.vue                          # MODIFIED: action-footer template restructure
├── ContactOpportunityCard.vue              # unchanged (out of scope per spec Assumptions)
└── ...

app/javascript/dashboard/routes/dashboard/opportunities/components/
└── StartOpportunityConversationButton.vue  # unchanged (consumed as-is inside footer row)
```

**Structure Decision**: Single-file, single-component change inside the existing
`components-next/Opportunities/` tree. No new files, directories, routes, or backend surface are
introduced. This is a pure frontend template/markup restructuring — no `contracts/` or
`data-model.md` content applies (both are marked N/A in Phase 1 output below).

## Complexity Tracking

*No Constitution Check violations — this section is intentionally empty.*
