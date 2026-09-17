# Data Model: Scout Overview — Summary Metrics & Funnel Distribution

## Existing Entities (read-only for this feature)

### Scout (`ichatr_scouts`)
| Column | Type | Notes |
|---|---|---|
| `id` | integer PK | |
| `account_id` | integer FK | |
| `name` | string | |
| `enabled` | boolean | disabled Scouts still have queryable history |
| `qualified_stage_id` | integer FK → `ichatr_pipeline_stages` | nullable; nil → rate shown as "—" |
| `unqualified_stage_id` | integer FK → `ichatr_pipeline_stages` | nullable |
| `rescue_stage_id` | integer FK → `ichatr_pipeline_stages` | nullable; Phase 22 abandonment stage |
| `interest_attribute_definition_id` | integer FK → `custom_attribute_definitions` | nullable |

**Associations used**:
- `has_many :scout_inboxes` → `has_many :inboxes, through: :scout_inboxes`
- `belongs_to :qualified_stage`, `unqualified_stage`, `rescue_stage` (optional)
- `belongs_to :interest_attribute_definition` (optional)

### ScoutInbox (`ichatr_scout_inboxes`)
| Column | Type | Notes |
|---|---|---|
| `scout_id` | integer FK | |
| `inbox_id` | integer FK | unique; one inbox → one scout |

**Role in this feature**: bridge table for the attribution JOIN.

### Opportunity (`ichatr_opportunities`)
| Column | Type | Notes |
|---|---|---|
| `id` | integer PK | |
| `account_id` | integer FK | |
| `pipeline_stage_id` | integer FK → `ichatr_pipeline_stages` | current stage |
| `origin_conversation_id` | integer FK → `conversations` | nullable; fixed at creation |
| `created_at` | datetime | period filter anchor |
| `custom_attributes` | jsonb | holds interest attribute value |

**Key behavior**: `origin_conversation_id` is set once at creation via `record_origin_conversation_link` callback and never retroactively changed — attribution to a Scout is stable.

### Conversation (`conversations`) — upstream table
| Column | Type | Notes |
|---|---|---|
| `id` | integer PK | |
| `inbox_id` | integer FK | links to `ScoutInbox` |

### Message (`messages`) — upstream table
| Column | Type | Notes |
|---|---|---|
| `conversation_id` | integer FK | |
| `message_type` | integer | 0=incoming, 1=outgoing, 2=activity; exclude type 2 |

### PipelineStage (`ichatr_pipeline_stages`)
| Column | Type | Notes |
|---|---|---|
| `id` | integer PK | |
| `account_id` | integer FK | |
| `name` | string | |
| `position` | integer | ordering; `default_scope { order(:position) }` |

### CustomAttributeDefinition (`custom_attribute_definitions`) — upstream table
| Column | Type | Notes |
|---|---|---|
| `id` | integer PK | |
| `attribute_key` | string | JSONB key used in `Opportunity.custom_attributes` |
| `attribute_display_type` | string | expected `'list'` for interest field |

---

## Derived Aggregates (computed on demand, not persisted)

No new database tables. All aggregations are computed at request time by `Reports::ScoutOverviewBuilder`.

### Attribution Scope (base relation used by all metrics)

```ruby
# "All opportunities handled by scout" — full lifetime, no date filter
def scout_handled_scope
  account.opportunities
         .joins(origin_conversation: :inbox)
         .where(inboxes: { id: scout.inboxes.select(:id) })
end

# "Opportunities handled by scout AND created in the period" — for summary cards.
# Covers ALL pipeline stages including In Progress (neither qualified, disqualified, nor abandoned).
def period_scope
  scout_handled_scope.where(created_at: range)
end
```

### Summary Metrics

| Metric | Formula | Nil condition | Notes |
|---|---|---|---|
| `total_handled` | `period_scope.count` | always integer ≥ 0 | Total opportunities created in the period by the Scout across all stages (including In Progress). Serves as the universal rate denominator. |
| `qualification_rate` | `(qualified_count.to_f / total_handled * 100).round(2)` | `nil` when `scout.qualified_stage_id.nil?` OR `total_handled == 0` | Opportunities that reached `scout.qualified_stage_id` ÷ `total_handled`. |
| `disqualification_rate` | `(unqualified_count.to_f / total_handled * 100).round(2)` | `nil` when `scout.unqualified_stage_id.nil?` OR `total_handled == 0` | Opportunities that reached `scout.unqualified_stage_id` ÷ `total_handled`. |
| `abandonment_rate` | `(rescue_count.to_f / total_handled * 100).round(2)` | `nil` when `scout.rescue_stage_id.nil?` OR `total_handled == 0` | Opportunities that reached `scout.rescue_stage_id` (Phase 22 inactivity rescue) ÷ `total_handled`. |
| `avg_messages_per_conversation` | `AVG(msg_count)` subquery over origin_conversations of period opps, excluding `message_type = 2` | `nil` when no conversations in period | Counts conversational turns (incoming + outgoing), excluding activity/system messages. |

**Denominator and In Progress semantics (Clarification 2026-09-16)**:
- `total_handled` is the single denominator for all three rate cards.
- Because opportunities still **In Progress** are counted in `total_handled` but do not belong to any outcome stage, `qualification_rate + disqualification_rate + abandonment_rate` may sum to less than 100% (the remainder represents in-progress volume).
- **Division-by-zero guard**: rates return `nil` (not 0.0) when either the stage is unconfigured or the total is zero. The frontend renders `nil` as `"—"`.
### Pipeline-Stage Distribution

```
[
  { stage_id: 1, stage_name: "Novo", stage_position: 0, count: 12 },
  { stage_id: 2, stage_name: "Qualificado", stage_position: 1, count: 7 },
  ...
]
```

- Source: `scout_handled_scope` (no period filter — current snapshot)
- `GROUP BY pipeline_stage_id`
- Joined to `PipelineStage` for `name` and `position`
- Sorted by `position ASC` (matches `default_scope`)
- Stages with 0 Scout-handled opportunities are **included** (count: 0) so the chart doesn't shift columns on Scout switch

### Interest-by-Stage Distribution

Two forms depending on `scout.interest_attribute_definition`:

**Configured** (`interest_attribute_definition` present):
```
{
  configured: true,
  attribute_name: "Produto",
  data: [
    {
      stage_id: 1, stage_name: "Novo",
      breakdown: { "Seguro" => 4, "Financiamento" => 2, null => 1 }
    },
    ...
  ]
}
```
- Source: `scout_handled_scope` (no period filter — same current-snapshot semantics as distribution chart)
- `GROUP BY pipeline_stage_id, custom_attributes->>'<attribute_key>'`
- `null` key covers opportunities with no value for the attribute
- Sorted by stage position

**Not configured**:
```
{ configured: false }
```

---

## Validation Rules

| Rule | Enforcement |
|---|---|
| `scout_id` required | controller param guard: `render 422` if blank or not found in account |
| `range` required | `DateRangeHelper#range` returns nil for unknown values; controller guards with `render 422` |
| Scout must belong to account | `Current.account.scouts.find(params[:scout_id])` — raises `ActiveRecord::RecordNotFound` → 404 |

---

## Authorization & Access Model (Clarification 2026-09-16 / FR-015)

| Role | Access | Enforcement |
|---|---|---|
| `administrator` | Allowed | `authorize :scout, :show?` via `ScoutPolicy` (`@account_user.present?`) |
| `agent` | Allowed | `authorize :scout, :show?` via `ScoutPolicy` (`@account_user.present?`) |
| `custom_role` (account member) | Allowed | `authorize :scout, :show?` via `ScoutPolicy` (`@account_user.present?`) |
| Non-member / unauthenticated | Denied | Handled by `BaseController` auth + Pundit (401 / 403) |

*Note*: Standard Chatwoot report policies (`ReportPolicy#view?`) enforce `@account_user.administrator?`. Following Captain Overview and the explicit clarification, Scout Overview intentionally permits both agents and administrators via `ScoutPolicy#show?`.

---

## Scale & Performance Characteristics (Clarification SC-002)

- **Production Dataset Scale**: Up to ~10,000 opportunities per account.
- **Attribution Index**: `ichatr_opportunities.origin_conversation_id` has a unique partial index (`WHERE origin_conversation_id IS NOT NULL`).
- **Stage Index**: `ichatr_opportunities.pipeline_stage_id` has an index.
- **Query Complexity**:
  - Summary metrics: 1 indexed `GROUP BY pipeline_stage_id` query + 1 messages aggregate query.
  - Pipeline distribution: 1 indexed `GROUP BY pipeline_stage_id` query over full lifetime scope.
  - Interest distribution: 1 indexed `GROUP BY pipeline_stage_id, custom_attributes->>'key'` query.
- **Latency Target**: On-demand execution takes < 40ms in PostgreSQL; end-to-end response < 100ms on localhost/LAN, well within the 2.0s requirement of SC-002.

---

## State Transitions (not applicable)

This feature is read-only. No state is written or transitioned. Attribution is anchored at opportunity creation time.

