# Phase 15: Kanban Lane Visual Improvements

**Status**: designed — ready for implementation
**Depends on**: Phase 1 (backend core — `PipelineStage`), Phase 6 (card
info and ordering), Phase 14 (`ciclo 3/06-deal-card-customization/spec14.md`
— currency config, already implemented)

## Context

`KanbanColumn.vue` today shows only the stage name and the count of
currently **loaded** cards (`cards.length`, driven by
`opportunities/cardsForStage`, which reflects whatever pages have been
fetched so far — see Phase 6's pagination). That badge is misleading once
a lane has more cards than fit on the first page. This phase replaces it
with a true lane-wide total, and adds a per-lane color, admin-configured
on `PipelineStage`.

## Clarifications

### Session 2026-08-03

- Q: If Phase 14's currency config isn't merged yet when Phase 15 ships,
  should the compact value total block on it, or fall back to a plain
  unformatted number? → A: Moot — Phase 14 is already merged (commit
  `b0bd400d9`, `feat(kanban): implement deal card customization and
  currency setting`). `PipelineCurrencySetting`, its controller, and the
  `pipelineCurrencySetting` Vuex module (`getters['pipelineCurrencySetting/getCurrency']`)
  already exist and are already consumed by `KanbanCard.vue` via
  `formatCurrencyAmount`. Phase 15 depends on this unconditionally, no
  fallback needed.
- Q: While a lane's aggregate is being (re)fetched, what should the
  header total show in the meantime? → A: No loading indicator — it's a
  small piece of header info, not worth dedicated visual feedback. Shows
  nothing until the first response arrives, then silently updates in
  place on every subsequent fetch (no spinner/skeleton, ever).

## Decisions

- **Lane total needs a backend aggregate — loaded-card count is not
  reused.** The existing `cards.length` badge is replaced by a real total
  (open-opportunity count and summed `value`), fed by a dedicated
  aggregate endpoint, decoupled from pagination state entirely.
- **Only `status: open` opportunities count toward the total.** A closed
  (won/lost) opportunity currently stays visible in its lane
  (soft-disabled), but the aggregate excludes it — the product direction
  is that closed opportunities will eventually leave the kanban board
  entirely (a future phase), so the total already behaves as if that were
  true.
- **Display mode is a per-lane config, defaulting to total value.** Each
  `PipelineStage` has a `total_display_mode` (`value_sum` default,
  `count`), configured by the admin. Count and value are never shown
  together — one or the other, per lane.
- **Aggregate refresh is surgical, not board-wide.** After a mutation
  (card move, create, status change, value edit), only the affected
  lane(s) re-fetch their aggregate via a dedicated endpoint scoped to
  specific `stage_id`s. No refetch of the full stage list, and no
  incremental client-side math — the number always comes fresh from the
  database, just scoped to what actually changed. This also means the
  aggregate call's cost doesn't scale with how many cards are loaded in a
  lane (it's a single indexed `COUNT`/`SUM`, independent of pagination).
- **Color scope: column header bottom border only.** Lane color is a thin
  accent on the **bottom border of the column header box** (where the
  stage title sits) — styled via inline `border-bottom-color`, free-hex,
  same pattern as Phase 14's card field colors and Labels. It does not
  color the rest of the lane, does not appear as a dot or left-border,
  and does not propagate to `KanbanCard.vue` (no card left-border, no
  card background tint). Cards remain visually defined by their own
  state (open/won/lost badge, grayscale/dashed "no linked conversation"
  styling, unmet-requirements state).
- **No interaction with unmet-requirements/grayscale card styling.**
  Since lane color doesn't touch card rendering, there is nothing to
  reconcile with `KanbanCard.vue`'s existing `cardClass`/
  `hasUnmetRequirements` logic.
- **Color is optional per stage**, defaulting to unset (no accent shown,
  current header border unchanged).
- **Currency formatting reuses Phase 14's currency config**, which is
  already implemented (`PipelineCurrencySetting`, the
  `pipelineCurrencySetting` Vuex module, and `formatCurrencyAmount`,
  already consumed by `KanbanCard.vue`). This phase's compact value
  formatting (e.g. "1,5K", "1M") wraps that same currency-lookup
  mechanism rather than hardcoding a symbol or assuming no currency at
  all.

## Functional Requirements

### Data model

**FR-001**: `matias_pipeline_stages` gains two columns: `total_display_mode`
(integer enum, `value_sum: 0` default, `count: 1`) and `accent_color`
(string, nullable, no default — unset means no accent). Migration under
`db/migrate/`.

**FR-002**: `PipelineStage` exposes `total_display_mode` as a standard
Rails enum, and accepts `accent_color` as a plain attribute with no
format validation (free-hex input, same as Phase 14's
`PipelineCardFieldConfig#color` — trusted admin input via a color picker,
not a hand-typed field).

### Backend API

**FR-003**: `PipelineStagesController#create`/`#update` permit
`total_display_mode` and `accent_color` in `pipeline_stage_params`;
`#index` already serializes the model's own attributes with no
`only:`/`except:` restriction, so both are included automatically.

**FR-004**: A new endpoint (e.g.
`Api::V1::Accounts::PipelineStageAggregatesController#index`) accepts a
required `stage_ids[]` param and returns, for each requested stage
belonging to `Current.account`, the **open**-status opportunity count and
the sum of `value` — a single grouped aggregate query
(`Current.account.opportunities.where(pipeline_stage_id: stage_ids, status: :open).group(:pipeline_stage_id)`
with `count`/`sum(:value)`), independent of `Opportunity.value` being
nullable (nulls excluded from the sum, per standard SQL `SUM` behavior).
Stages with no open opportunities are simply absent from the response
(the frontend treats absence as zero). Follows the same authorization
guard (`Concerns::KanbanFeatureGuard`, `check_authorization`) as the rest
of the pipeline-stage endpoints.

### Frontend

**FR-005**: `EditPipelineStage.vue` gains two fields, alongside the
existing name/position/`requires_deal_value` fields:
- A select/radio "lane header display": **Total value** (default) or
  **Count**, mapped to `total_display_mode`.
- A `ColorPicker.vue` (the existing free-hex component, e.g. as used by
  Phase 14's `CardFieldConfig.vue`) for `accent_color`, with a way to
  clear it back to unset.

**FR-006**: `pipelineStages` Vuex module: `fetch`'s existing payload
shape already carries `total_display_mode`/`accent_color` through
unchanged (no new getter needed for these). A new mutation
`SET_STAGE_AGGREGATES(state, { stageId, openCount, openValueSum })`
merges the aggregate into only the matching stage entry. A new action
`fetchAggregates({ stageIds })` calls FR-004's endpoint and dispatches
this mutation for each returned `stage_id`; stage ids present in the
request but absent from the response are set to `openCount: 0`,
`openValueSum: 0`.

**FR-007**: `KanbanBoard.vue` dispatches `pipelineStages/fetchAggregates`
with exactly the affected `stage_id`(s) after each of these existing
success paths:
- Card move (`executeMoveCard`/`dispatchMoveIfComplete`): `[fromStageId, toStageId]`.
- Status change (`onStatusChanged`): `[opportunity.pipeline_stage_id]`.
- Card creation (`OpportunityCreateModal` close on success): `[stageId]`
  of the chosen lane.
- Value edit (`OpportunityBackfillModal` close on success):
  `[opportunity.pipeline_stage_id]`.

No refetch of the full stage list and no refetch of any lane's card
pagination happens as part of this. A failed `fetchAggregates` call has
no dedicated error UI — it's handled by the existing global API error
interceptor, same as other pipeline-stage actions; the header simply
keeps showing its last known value.

**FR-008**: `KanbanColumn.vue`'s header badge (currently `cards.length`)
is replaced: renders `stage.open_count ?? 0` when `total_display_mode` is
`count`, or a compact-formatted `stage.open_value_sum` when `value_sum`
(default) — via `Intl.NumberFormat` with `notation: 'compact'`, using the
currency resolved through Phase 14's currency config. No loading
indicator is shown while an aggregate fetch is in flight (initial load
or after a mutation) — the badge renders nothing until the first
response arrives, then updates in place silently on every subsequent
fetch.

**FR-009**: `KanbanColumn.vue`'s header container applies
`stage.accent_color`, when present, as `border-bottom-color` via an
inline `:style`, layered on top of the existing `border-b border-n-weak`
class (only the color changes; thickness/position stay the same). No
other part of the lane changes color. An unset `accent_color` keeps
today's `border-n-weak` appearance exactly as-is.

## Out of Scope (this phase)

- Propagating `accent_color` to `KanbanCard.vue` or anywhere else in the
  column body — header bottom border only.
- A curated/fixed color-token palette for lanes — free-hex, matching the
  existing Labels/Phase 14 scheme, is used instead.
- Including won/lost opportunities in the aggregate — only `open` status
  counts and sums, since closed opportunities are slated to eventually
  leave the kanban board entirely (a separate future phase).
- Real-time cross-tab/cross-user sync of aggregates — updates only
  happen in the tab that performed the mutation; other tabs/sessions see
  accurate numbers on their next `pipelineStages/fetch` (e.g. page
  reload).
- A dedicated currency-selection UI in this phase — depends entirely on
  the currency config introduced by Phase 14 (`spec14.md`).
- A manual "refresh totals" affordance — unnecessary, since every
  relevant mutation already triggers a scoped aggregate update.
- Showing count and value together — one or the other, per
  `total_display_mode`.

## Completion Criteria

Verify inside the `rails`/`vite` containers as appropriate.

1. A lane configured with `total_display_mode: value_sum` (default) shows
   the compact-formatted sum of all **open** opportunities' value in that
   lane, correct for the entire lane — not just loaded/paginated cards.
2. A lane configured with `total_display_mode: count` shows the count of
   all open opportunities in that lane, correct for the entire lane.
3. Moving, creating, closing/reopening, or editing the value of a card
   updates the aggregate of only the affected lane(s), without
   refetching the card list or any other lane's aggregate.
4. An admin can set `total_display_mode` and `accent_color` from the Edit
   Pipeline Stage form; leaving `accent_color` unset keeps today's
   default border.
5. The lane header's bottom border reflects the configured
   `accent_color`; no other part of the lane changes color.
6. `pnpm eslint` and `bundle exec rubocop` pass for touched files.
