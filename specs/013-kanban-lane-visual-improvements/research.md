# Research: Kanban Lane Visual Improvements

No `NEEDS CLARIFICATION` markers remain in the Technical Context — the source design doc
(`docs/kanban/ciclo 3/07-kanban-lane-visual-improvements/spec15.md`) already resolved every open
question during its own design/clarification pass. This document records the resulting decisions
and their rationale for traceability.

## Decision: Lane total is served by a dedicated backend aggregate, not derived from loaded cards

**Rationale**: `KanbanColumn.vue`'s current badge reads `cards.length`, which reflects only
`opportunities/cardsForStage` — whatever pages have been fetched by `IntersectionObserver`-driven
pagination (see `KanbanColumn.vue:29-58`). This is already wrong once a lane exceeds one page.
Reusing the loaded-card count is not an option; the total must come from the database,
independent of pagination state.

**Alternatives considered**: Client-side incremental math (track a running total and adjust on
each mutation) was rejected — it would drift from reality on any missed event, cross-tab change,
or bug, and the aggregate query is already cheap (single indexed `COUNT`/`SUM`), so there's no
performance reason to avoid always refetching fresh.

## Decision: Aggregate query is grouped and scoped to explicit `stage_ids[]`, not per-stage N+1 calls

**Rationale**: A single `Current.account.opportunities.where(pipeline_stage_id: stage_ids, status:
:open).group(:pipeline_stage_id)` with `count`/`sum(:value)` serves all initially-visible stages
in one request, and just the 1-2 affected stages after a mutation — matching the "surgical
refresh" decision (only affected lanes re-fetch, not the whole board).

**Alternatives considered**: Embedding the aggregate directly into `PipelineStagesController#index`'s
existing payload was considered (Option B during clarification) but rejected in favor of a
dedicated endpoint — it keeps the expensive/volatile aggregate query decoupled from the
relatively static stage-config payload, and allows the surgical per-mutation refresh to hit a
narrow endpoint instead of re-fetching all stage config.

## Decision: Currency formatting reuses Phase 14's already-shipped infrastructure unconditionally

**Rationale**: Verified via `git log` (commit `b0bd400d9`) and direct file inspection that
`PipelineCurrencySetting`, its controller, the `pipelineCurrencySetting` Vuex module, and
`formatCurrencyAmount` (already consumed by `KanbanCard.vue`, see
`app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue:89-91,108`) are fully
merged. No fallback/feature-detection is needed — this phase depends on that infrastructure
directly, same as `KanbanCard.vue` already does.

## Decision: Lane color is scoped to the column header's bottom border only

**Rationale**: `KanbanCard.vue`'s existing `cardClass` computed (lines 40-53) already encodes
card-level visual state (grayscale/dashed for no-linked-conversation, `is-closed` for won/lost).
Introducing lane color into card rendering would require reconciling with that logic. Scoping
color to `KanbanColumn.vue`'s header container avoids this entirely — an inline
`border-bottom-color` layered on the existing `border-b border-n-weak` class, matching the
established free-hex pattern already used by Labels and Phase 14's card-field colors.

**Alternatives considered**: A colored dot/badge next to the stage name, or a left-border accent
on the whole column, were considered less clean since they'd compete visually with the existing
header content (name, total badge, add-card button); bottom-border was chosen as the least
intrusive option matching precedent (`border-b border-n-weak` already exists on the header).

## Decision: No loading indicator for the header total; no dedicated error UI on refresh failure

**Rationale**: Explicit user direction during clarification — this is "a very small piece of
header info" not warranting dedicated visual feedback. The header keeps its last known value
until a new one arrives, updating silently. A failed refresh falls back to the existing global API
error interceptor (same handling as other pipeline-stage actions), rather than adding new
per-component error UI.

**Alternatives considered**: A skeleton/spinner state and a dedicated inline error message were
both considered and explicitly rejected by the user as unnecessary for information this minor.
