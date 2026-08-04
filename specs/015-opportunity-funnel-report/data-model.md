# Phase 1 Data Model: Opportunity Funnel Report

## Opportunity (extended)

**Table**: `matias_opportunities` (existing)

New column:

| Field | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `closed_at` | datetime | yes | `nil` | Set to `Time.current` when `status` transitions `open` → `won`/`lost`; cleared back to `nil` if a closed opportunity is reopened (`status` transitions back to `open`). |

**New callback** (`before_save`, in addition to existing callbacks):

```
before_save :set_or_clear_closed_at, if: :status_changed?
```

- `status` becomes `won` or `lost` (from `open`) → `self.closed_at = Time.current`
- `status` becomes `open` (from `won`/`lost`) → `self.closed_at = nil`
- Any other status transition (there are only these three states) → no-op

**Indexes**: `[account_id, closed_at]` — supports the win-rate,
sales-cycle-time, and performance-by-assignee queries, all of which filter
`closed_at` within a period for a given account.

**No new associations.** No change to `stage_changes`
(`OpportunityStageChange`, from Phase 11) — the funnel builder reads that
existing association read-only.

## Reports::OpportunityFunnelBuilder (new service, not a persisted model)

Not an ActiveRecord model — a plain Ruby service object,
`pattr_initialize :account, :range`, with one public method (`build` or
similarly named) returning a single hash keyed exactly as FR-004 specifies.
The controller (`Api::V1::Accounts::OpportunityFunnelReportsController#index`)
is the one that resolves `since`/`until` via `DateRangeHelper` — mirroring
where `DateRangeHelper` is invoked everywhere else in this codebase — and
passes the already-parsed range into the builder; the builder itself does no
param parsing. `pattr_initialize` is kept (rather than the plain
`def initialize(**context)` style `Reports::DataSource` — the core sibling
this module reopens — happens to use) because it is the fork's own
established convention across `custom/`, used 131 times elsewhere in this
repo; this is a deliberate choice, not an oversight.

```ruby
{
  conversion_funnel: { labels: [...], data: [...] },
  win_rate: { won: Integer, lost: Integer },
  pipeline_value_by_stage: { labels: [...], data: [...] },
  avg_time_in_stage: { labels: [...], data: [...] },
  new_opportunities_over_time: { labels: [...], data: [...] },
  sales_cycle_time: { average_days: Float | nil },
  performance_by_assignee: [{ assignee_id:, assignee_name:, count:, value: }, ...]
}
```

Each of the 7 keys is computed independently by a private method on the
builder; none share query state beyond the `account` and parsed `range`
(via `DateRangeHelper`). Field/key names above are illustrative — see
`contracts/opportunity_funnel_report.md` for the authoritative response
shape.

### Per-metric data sources (read-only queries, no new tables)

| Metric | Source | Period-scoped? |
|---|---|---|
| `conversion_funnel` | `Opportunity` (created_at in range) joined against `OpportunityStageChange` per stage reach | Yes (created-in-period) |
| `win_rate` | `Opportunity` (`closed_at` in range, status won/lost) | Yes (closed-in-period) |
| `pipeline_value_by_stage` | `Opportunity` (status: open), grouped by `pipeline_stage_id` | No (current state) |
| `avg_time_in_stage` | `OpportunityStageChange`, self-joined per opportunity on consecutive `changed_at` | No (lifetime average) |
| `new_opportunities_over_time` | `Opportunity` (created_at in range), grouped by day | Yes (created-in-period) |
| `sales_cycle_time` | `Opportunity` (`closed_at` in range, status won) | Yes (closed-in-period) |
| `performance_by_assignee` | `Opportunity` (`closed_at` in range, status won), grouped by `assignee_id` | Yes (closed-in-period) |

## Key Entities (unchanged, read-only from this feature's perspective)

- **PipelineStage** (`matias_pipeline_stages`, existing) — read for `position`
  (funnel ordering) and `id`/`name` (chart labels). No schema change.
- **OpportunityStageChange** (`matias_opportunity_stage_changes`, existing,
  from Phase 11) — read for `to_stage_id`/`changed_at` to compute funnel
  reach and average time-in-stage. No schema change.
- **User** (assignee, core/upstream, existing) — read for
  `assignee_id`/`name` in `performance_by_assignee`. No schema change.

## Validation rules

No new user-writable input beyond the existing `since`/`until` params
(already validated by `DateRangeHelper`, unmodified). The `closed_at`
column itself is never directly settable via controller params — it is
exclusively callback-derived, matching how `current_stage_entered_at` is
exclusively derived from `OpportunityStageChange` in Phase 11.

## State transitions

`closed_at` state (of `Opportunity`, extending the existing `status` enum's
lifecycle):

1. `status: open → won` or `open → lost` → `closed_at: nil → Time.current`
2. `status: won → open` or `lost → open` (reopen) → `closed_at: <timestamp> → nil`
3. `status: won → lost` or `lost → won` (switching outcome without
   reopening first) → no-op; `closed_at` is left as-is, since FR-002 only
   defines the transition trigger as "from open," and this direct
   won↔lost path isn't reachable through the existing kanban/API status
   transition UI today.
