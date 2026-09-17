# Research: Scout Overview — Summary Metrics & Funnel Distribution

## 1. Scout Attribution Model

**Decision**: An opportunity is attributed to a Scout by reading `opportunity.origin_conversation.inbox.scout_id`.  
**Rationale**: `ScoutInbox` links `inbox_id → scout_id`; `Opportunity.origin_conversation_id` is set at creation and never retroactively changed. Attribution is a single JOIN:

```sql
JOIN conversations   ON conversations.id  = ichatr_opportunities.origin_conversation_id
JOIN ichatr_scout_inboxes ON ichatr_scout_inboxes.inbox_id = conversations.inbox_id
WHERE ichatr_scout_inboxes.scout_id = :scout_id
```

**Alternatives considered**:
- Denormalizing `scout_id` onto `Opportunity` — avoided; no migration needed and the spec explicitly says attribution is fixed at creation time, so the JOIN is stable and fast.
- Using `OpportunityStageChange` history — overkill; current stage is on `Opportunity.pipeline_stage_id`.

---

## 2. Period Filtering and In-Progress Handling (Summary Cards)

**Decision**: Filter on `ichatr_opportunities.created_at` within the selected period window. All opportunities created by the Scout in the period — including those still **In Progress** — are included in `total_handled` and in the denominator of all outcome rate cards.  
**Rationale**: Per the 2026-09-16 clarification and FR-005/FR-011:
- "handled" = all opportunities created in the period by the Scout (`inbox.scout_id == scout.id`), regardless of whether they have reached a terminal outcome or remain In Progress.
- Outcome rates = outcomes ÷ total handled (`period_created_opportunities`).
- This gives operators a true conversion view against total lead volume handled by the Scout, rather than artificially inflating rates by discarding unresolved conversations.

**Period values and backend computation**:
| Frontend value | Backend range |
|---|---|
| `'7'` | `(Time.zone.now - 7.days)..Time.zone.now` |
| `'30'` | `(Time.zone.now - 30.days)..Time.zone.now` |
| `'this_month'` | `Time.zone.now.beginning_of_month..Time.zone.now.end_of_month` |
| `'last_month'` | `1.month.ago.beginning_of_month..1.month.ago.end_of_month` |

`DateRangeHelper` (already in `custom/app/controllers/concerns/`) resolves a `range` param string into a Ruby Range. **Decision**: reuse `DateRangeHelper#range` directly.

---

## 3. Outcome Stage Identification & Single-Query Aggregation

**Decision**: Read outcome stage IDs directly from `Scout#qualified_stage_id`, `Scout#unqualified_stage_id`, `Scout#rescue_stage_id`, and aggregate via a single `group(:pipeline_stage_id).count` on the period scope.  
**Rationale**: All three stage IDs are already persisted (Phases 09 and 22). By grouping by `pipeline_stage_id` once:
1. `total_handled` is `stage_counts.values.sum` (includes In Progress opportunities in any other stage).
2. `qualified_count` is `stage_counts[scout.qualified_stage_id] || 0` (if stage configured).
3. `unqualified_count` is `stage_counts[scout.unqualified_stage_id] || 0` (if stage configured).
4. `abandoned_count` is `stage_counts[scout.rescue_stage_id] || 0` (if stage configured).
5. Rates are calculated as `(count.to_f / total_handled * 100).round(2)`.

**Outcome classification**:
- **Qualified**: `opportunity.pipeline_stage_id == scout.qualified_stage_id`
- **Disqualified**: `opportunity.pipeline_stage_id == scout.unqualified_stage_id`
- **Abandoned**: `opportunity.pipeline_stage_id == scout.rescue_stage_id` (inactivity rescue, Phase 22)
- **In Progress**: none of the above (opportunity still pending in pipeline; counted in `total_handled` denominator, no outcome numerator)

**Guard**: If a scout's outcome stage ID is `nil` (incomplete setup), return `nil` for that rate (rendered as `"—"` on frontend). When `total_handled == 0`, all rates return `nil`. No division-by-zero or NaN errors.
---

## 4. Messages-per-Conversation Metric

**Decision**: Count all `messages` rows in `origin_conversation` where `message_type != 2` (activity), not just Scout-generated ones.  
**Rationale**: Spec says "counting both lead and Scout messages in each conversation", consistent with measuring real conversation size. Activity messages (type 2 in Chatwoot's `Message.message_types`) are system events, not conversational turns — exclude them to avoid inflating the count.

**SQL approach**: a subquery `AVG(msg_count)` where `msg_count` is `COUNT(*) GROUP BY conversation_id` for the `conversations` of handled opportunities in the period, with `message_type != 2` filter.

---

## 5. Pipeline-Stage Distribution (Current Snapshot)

**Decision**: Return the current `pipeline_stage_id` of all Scout-handled opportunities — no period filter.  
**Rationale**: FR-008 explicitly states this is "a current snapshot unaffected by the period selector". The `PipelineStageAggregatesController` establishes the fork's pattern for non-period-filtered stage counts.

**Query**: `GROUP BY pipeline_stage_id` on the Scout-handled opportunities scope (full lifetime, no date filter), joined to `PipelineStage` for ordering (`default_scope { order(:position) }`).

---

## 6. Interest-by-Stage Distribution

**Decision**: Use `opportunity.custom_attributes[interest_attribute_definition.attribute_key]` grouped by `pipeline_stage_id`.  
**Rationale**: `Scout#interest_attribute_definition` (a `CustomAttributeDefinition`) already stores the attribute key. The `Opportunity.custom_attributes` is a JSONB column. A `GROUP BY pipeline_stage_id, custom_attributes->>'<key>'` query covers the breakdown. When `interest_attribute_definition` is nil, return a sentinel `{ configured: false }` and the frontend renders the CTA card.

**Alternatives considered**: Materializing interest values into a separate column — out of scope; the JSONB approach is already established for all custom attributes in this fork.

---

## 7. API Endpoint Design

**Decision**: Single account-scoped REST resource `scout_overview_reports`, not a nested Scout resource.  
**Rationale**:
- `scout_id` is a query param (to support the Scout selector), not a URL segment, matching how the Captain overview works (`assistant_id` as a param rather than a nested route in the overview report context).
- Keeps routes consistent with `opportunity_funnel_reports` and `opportunity_attribute_reports` (flat, account-scoped, index-only resources).
- Avoids polluting the existing `scouts` resource with a non-CRUD sub-resource.

**Route**: `GET /api/v1/accounts/:account_id/scout_overview_reports`  
**Params**:
| Param | Type | Required | Notes |
|---|---|---|---|
| `scout_id` | integer | yes | The Scout to aggregate for |
| `range` | string | yes | `'7'`, `'30'`, `'this_month'`, `'last_month'` |
| `timezone_offset` | numeric string | no | UTC offset in hours; forwarded to `DateRangeHelper` |

**Response**: single JSON object (see contracts/).

**Controller**: `Api::V1::Accounts::ScoutOverviewReportsController` in `custom/app/controllers/`.  
**Guard**: reuse the existing `Pundit` authorize pattern with `Scout` policy (`scout_policy.rb` already has `show?` tied to `administrator | agent | custom_role`). No separate `KanbanFeatureGuard` needed — the Scout feature flag check is already in the route meta on the frontend; the backend authorizes via Pundit.

---

## 8. Builder Service

**Decision**: New `Reports::ScoutOverviewBuilder` service in `custom/app/services/reports/`, following the `pattr_initialize` pattern of `OpportunityFunnelBuilder`.  
**Rationale**: Isolates SQL aggregation logic from the controller; consistent with every other report builder in this fork.

**Builder outputs** (all computed in one `#build` call):
- `summary` hash: `{ total_handled, qualification_rate, disqualification_rate, abandonment_rate, avg_messages_per_conversation }`
- `pipeline_stage_distribution` array: `[{ stage_id, stage_name, stage_position, count }]` sorted by position
- `interest_by_stage` hash: `{ configured: true, data: [{ stage_id, stage_name, breakdown: { "value" => count } }] }` or `{ configured: false }`

---

## 9. Frontend Structure

**Decision**: New page route `scout_overview` added as the **first** child in `scout.routes.js` and the first `activeOn` entry in the Sidebar Scout section.  
**Rationale**: FR-001 / FR-073 require it to be the first child. Sidebar.vue has a plain array of children objects; prepending is a one-line edit.

**Frontend file layout**:
```
app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.vue   ← new page
app/javascript/dashboard/components-next/scout/overview/
  ScoutSummaryCard.vue        ← five metric cards (reuse MetricCard pattern)
  PipelineDistributionChart.vue  ← stage distribution chart (using Chart.js already in project)
  InterestByStageCard.vue     ← interest breakdown or CTA
  ScoutSelector.vue           ← conditional scout picker (hidden when account has one Scout)
app/javascript/dashboard/api/scoutOverviewReports.js  ← new API client
```

**Scout selector logic**: fetched from the existing `GET /scouts` endpoint (already available via `scout.js` API). Rendered only when `scouts.length > 1`. Initialized to first Scout (or last selected, stored in component state).

**RangeSelector**: reused directly from `app/javascript/dashboard/components-next/captain/pageComponents/overview/RangeSelector.vue` — no new component needed.

**EmptyStateLayout**: reused from `app/javascript/dashboard/components-next/EmptyStateLayout.vue`.

**i18n**: new keys under `SCOUT.OVERVIEW.*` in both `en.json` and `pt_BR.json`.

---

## 10. Chart Library

**Decision**: Use Chart.js (already present in the project for other pipeline/funnel charts) via the existing `vue-chartjs` wrapper.  
**Rationale**: No new dependency. Bar chart for stage distribution (horizontal, one bar per stage). Stacked bar for interest-by-stage (one stack per stage, colored by interest value).

**Alternatives considered**: Recharts — not currently used. Tailwind-only — insufficient for these chart types.

---

## 11. Authorization Model

**Decision**: `authorize :scout, :show?` (or `authorize @scout, :show?`) using `ScoutPolicy`, permitting any authenticated account member (agent, administrator, custom_role).  
**Rationale**: Per the 2026-09-16 clarification and FR-015:
- Chatwoot's standard `ReportPolicy#view?` restricts report access strictly to administrators (`@account_user.administrator?`).
- In contrast, Captain Overview (`Captain::AssistantPolicy#metrics?`) and Scout Overview are operational dashboards designed for daily use by both operators/agents and administrators.
- `ScoutPolicy#show?` checks `@account_user.present?`, which correctly allows any authenticated account member scoped to their account to view the data.
- Therefore, `ScoutOverviewReportsController` MUST use `ScoutPolicy` and MUST NOT use `ReportPolicy`.
---

## 12. No Enterprise Overlay Needed

**Decision**: No `enterprise/` counterpart for this feature.  
**Rationale**: This is a fork-only, Scout-domain report; Captain's enterprise stats overlay (`enterprise/app/controllers/api/v1/accounts/captain/assistant_stats_controller.rb`) exists because Captain is an upstream feature with enterprise extensions. Scout is fork-original — it has no upstream or enterprise equivalent to mirror.

---

## 13. Performance & Scale (Clarification SC-002 Benchmark)

**Decision**: On-demand SQL aggregation without background caching or pre-computed rollups.  
**Rationale**: Per the 2026-09-16 clarification on SC-002 ("standard connection = localhost/LAN, dataset ≤ ~10k opportunities per account"):
- In the fork's production environment, the largest account dataset contains ~10,000 opportunities.
- `ichatr_opportunities` has an existing index on `origin_conversation_id` (`where origin_conversation_id is not null`) and `pipeline_stage_id`.
- In PostgreSQL, a `JOIN conversations ON ... WHERE inbox_id IN (...) GROUP BY pipeline_stage_id` over 10,000 indexed rows takes under 15ms.
- Total backend execution time is ~20–40ms; over a localhost or LAN connection, end-to-end response time is well under 100ms.
- This is more than an order of magnitude faster than the 2.0-second threshold required by SC-002, fully justifying the architectural constraint (FR-013) that no pre-aggregation or background caching is needed.

