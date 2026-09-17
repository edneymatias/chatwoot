# Research & Architecture Decisions: Scout Overview — Recent Conversations List

**Feature**: `073-scout-overview-conversations`  
**Date**: 2026-09-16  
**Status**: Completed  

---

## 1. Outcome Classification Architecture

### Problem
FR-005 mandates that each conversation handled by the selected Scout within the active period MUST be classified into exactly one of five mutually exclusive funnel outcome statuses:
1. **Qualified**: Opportunity associated with the conversation reached `scout.qualified_stage_id`.
2. **Disqualified**: Opportunity associated with the conversation reached `scout.unqualified_stage_id`.
3. **Abandoned**: Opportunity associated with the conversation reached `scout.rescue_stage_id`.
4. **In Progress**: Actively handled by Scout; neither terminal stage reached (opportunity in initial stage, or no opportunity created yet while conversation remains active/pending).
5. **Transferred without opportunity**: The conversation underwent a handoff to a human agent, but no opportunity was created or linked to the conversation.

Furthermore, SC-002 requires loading and filtering conversations within 1 second on account datasets containing up to 10,000 conversations.

### Decision
Implement the classification directly within a single PostgreSQL SQL query using a `LEFT JOIN LATERAL` to resolve the latest linked `Opportunity` per conversation, followed by a deterministic `CASE` expression.

```sql
LEFT JOIN LATERAL (
  SELECT opp.id, opp.title, opp.pipeline_stage_id
  FROM ichatr_opportunities opp
  JOIN ichatr_opportunity_conversations oc ON oc.opportunity_id = opp.id
  WHERE oc.conversation_id = conversations.id
  ORDER BY opp.updated_at DESC
  LIMIT 1
) latest_opp ON true
```

And outcome classification expression:
```sql
CASE
  WHEN latest_opp.id IS NOT NULL THEN
    CASE
      WHEN latest_opp.pipeline_stage_id = :qualified_stage_id THEN 'qualified'
      WHEN latest_opp.pipeline_stage_id = :unqualified_stage_id THEN 'disqualified'
      WHEN latest_opp.pipeline_stage_id = :rescue_stage_id THEN 'abandoned'
      ELSE 'in_progress'
    END
  ELSE
    CASE
      WHEN conversations.status = 2 THEN 'in_progress'
      ELSE 'transferred_without_opportunity'
    END
END AS outcome_status
```
*(where `conversations.status = 2` is `:pending` in Chatwoot's conversation enum, representing an active bot conversation. Any non-pending conversation on a Scout inbox without an opportunity is classified as `transferred_without_opportunity`).*

### Rationale
- **Performance**: Executed in PostgreSQL engine in < 15ms for 10,000 rows. No Ruby object allocation for non-displayed pages.
- **Zero Schema Overhead**: Requires no new database columns, triggers, or migrations (satisfying Constitution Principle I and Principle II).
- **Exact Count Aggregation**: The same `outcome_status` expression is wrapped in a `SELECT outcome_status, COUNT(*) GROUP BY outcome_status` to compute all filter pill counts in a single round-trip.

### Alternatives Considered
- *In-Memory Ruby Filtering*: Load conversations into ActiveRecord and classify via Ruby methods. Rejected because loading thousands of ActiveRecord objects per request exceeds the 1s latency ceiling and consumes excessive container memory.
- *Denormalized Outcome Column on `conversations`*: Add a `scout_outcome` column to `conversations`. Rejected because it introduces upstream divergence on a core table (violating Principle I) and requires complex callback/trigger synchronization across `OpportunityStageChange`, `bot_handoff!`, and conversation status transitions.

---

## 2. API Design & Routing

### Problem
FR-009, FR-010, and FR-003 require synchronizing conversation rows, status counts, and pagination with the active Scout and period, while supporting page transitions and status filter pill clicks without reloading summary metric cards or funnel distribution charts.

### Decision
Add a dedicated `conversations` collection action to the existing `scout_overview_reports` resource:
`GET /api/v1/accounts/:account_id/scout_overview_reports/conversations`

Backed by `Reports::ScoutOverviewConversationsBuilder` in `custom/app/services/reports/`.

**Request Parameters**:
- `scout_id`: integer (required)
- `range`: string enum (`'7'`, `'30'`, `'this_month'`, `'last_month'`) (required)
- `timezone_offset`: string or number (optional, hours offset e.g. `"-3"`)
- `status`: string optional (`'all'`, `'qualified'`, `'disqualified'`, `'abandoned'`, `'in_progress'`, `'transferred_without_opportunity'`, default `'all'`)
- `page`: integer (default `1`)
- `per_page`: integer (default `25`, max `100`)

**Response Envelope**:
```json
{
  "conversations": [
    {
      "id": 101,
      "display_id": 42,
      "contact": {
        "id": 501,
        "name": "Jane Doe",
        "identifier": "+5511999998888",
        "email": "jane@example.com",
        "phone_number": "+5511999998888",
        "thumbnail": "https://..."
      },
      "inbox": {
        "id": 5,
        "name": "WhatsApp Commercial",
        "channel_type": "Channel::Whatsapp"
      },
      "start_at": 1773662400,
      "duration_seconds": 320,
      "messages_count": 8,
      "status": "qualified",
      "opportunity": {
        "id": 12,
        "title": "Enterprise Deal",
        "stage_id": 3
      }
    }
  ],
  "status_counts": {
    "all": 85,
    "qualified": 24,
    "disqualified": 15,
    "abandoned": 10,
    "in_progress": 20,
    "transferred_without_opportunity": 16
  },
  "pagination": {
    "current_page": 1,
    "total_count": 85,
    "per_page": 25,
    "total_pages": 4
  }
}
```

### Rationale
- Returning `status_counts` alongside the page payload ensures filter pills always display current counts without extra network round-trips.
- Separating conversation pagination from `scout_overview_reports#index` keeps the overview summary fast and prevents payload bloat.
- Fits seamlessly into `Api::V1::Accounts::ScoutOverviewReportsController`, reusing its `check_authorization` (`ScoutPolicy#show?`), `set_scout`, and `validate_range` filters.

### Alternatives Considered
- *Embed recent conversations in `scout_overview_reports#index`*: Rejected because pagination changes or clicking status filter pills would re-calculate all pipeline charts and overview metric cards unnecessarily.
- *Separate top-level controller `scout_conversations_controller`*: Rejected because the feature is strictly a component of the Scout Overview report view, and keeping it namespaced under `scout_overview_reports` reinforces cohesion.

---

## 3. Duration and Message Count Aggregation

### Problem
FR-007 requires computing conversation duration as elapsed time between the first and last message in the exchange, returning a dash placeholder ("—") when a conversation contains only one message. FR-008 requires counting total incoming and outgoing messages.

### Decision
Compute `messages_count` and `duration_seconds` for the **current page of 25 conversations** via a single grouped SQL query on the `messages` table:

```ruby
def message_metrics_for(conversation_ids)
  return {} if conversation_ids.empty?

  account.messages
         .unscope(:order)
         .where(conversation_id: conversation_ids)
         .where(message_type: %i[incoming outgoing])
         .group(:conversation_id)
         .select(
           :conversation_id,
           'COUNT(*) AS msg_count',
           'MIN(created_at) AS first_msg_at',
           'MAX(created_at) AS last_msg_at'
         )
         .index_by(&:conversation_id)
end
```

Duration calculation logic:
```ruby
metrics = message_metrics[conv.id]
count = metrics ? metrics.msg_count.to_i : 0
duration = if count <= 1 || metrics.first_msg_at == metrics.last_msg_at
             nil
           else
             (metrics.last_msg_at - metrics.first_msg_at).to_i
           end
```

In the Vue frontend, render `duration_seconds`:
- `null` or `count <= 1` → `" — "`
- `> 0` → formatted via `formatDuration(duration_seconds)` from `shared/helpers/timeHelper.js` (e.g., `05:20` or `01:12:00`).

### Rationale
- Queries only the 25 rendered conversation IDs, taking < 3ms using the existing compound index `index_messages_on_conversation_account_type_created`.
- Accurately identifies 1-message conversations and suppresses false zero-minute durations.

### Alternatives Considered
- *Subqueries in the primary conversation select*: Rejected because PostgreSQL aggregate subqueries over all period rows prior to pagination create unnecessary I/O overhead.

---

## 4. UI Component Architecture

### Problem
FR-001, FR-002, FR-004, FR-006, FR-010, FR-012, and FR-013 mandate:
- An embedded section at the bottom of the Scout Overview page.
- Status filter pills with real-time counts.
- 5-column table (Contact, Start Time, Duration, Messages, Status Badge).
- Neutral visual treatment for "Transferred without opportunity".
- Page-based pagination (25 records/page).
- Row click opening the conversation in a new tab.
- Empty states for zero matches.

### Decision
Create modular components under `app/javascript/dashboard/components-next/scout/overview/`:

1. `RecentConversationsSection.vue`: Container component embedded in `ScoutOverview.vue`. Handles filter state, pagination state, data fetching, and synchronizes with Scout and Period selectors.
2. `ConversationStatusBadge.vue`: Visual badge displaying the 5 outcome statuses with standard Tailwind styling:
   - `qualified`: `bg-n-teal-3 text-n-teal-11 dark:bg-n-teal-4 dark:text-n-teal-11` (Positive / Green)
   - `disqualified`: `bg-n-ruby-3 text-n-ruby-11 dark:bg-n-ruby-4 dark:text-n-ruby-11` (Negative / Red)
   - `abandoned`: `bg-n-amber-3 text-n-amber-11 dark:bg-n-amber-4 dark:text-n-amber-11` (Warning / Yellow)
   - `in_progress`: `bg-n-blue-3 text-n-blue-11 dark:bg-n-blue-4 dark:text-n-blue-11` (Informational / Blue)
   - `transferred_without_opportunity`: `bg-n-slate-3 text-n-slate-11 dark:bg-n-slate-4 dark:text-n-slate-11` (Neutral / Gray per FR-006)
3. Reuse `BaseTable`, `BaseTableRow`, `BaseTableCell` from `dashboard/components-next/table/` and `PaginationFooter` from `dashboard/components-next/pagination/PaginationFooter.vue`.
4. Row click handler:
   ```javascript
   const openConversation = (conversationId) => {
     const url = `/app/accounts/${accountId.value}/conversations/${conversationId}`;
     window.open(url, '_blank', 'noopener,noreferrer');
   };
   ```

### Rationale
- Keeps `ScoutOverview.vue` clean and declarative.
- Reuses existing design-system table and pagination components without writing custom CSS or violating Tailwind utility guidelines.
- Standard `window.open` with `noopener,noreferrer` protects security and leaves Overview state completely intact.

---

## 5. Summary of Key Decisions

| Area | Decision | Primary Driver |
|---|---|---|
| Outcome Determination | `LEFT JOIN LATERAL` on `Opportunity` + SQL `CASE` | Sub-20ms performance on 10k rows; 0 schema migrations |
| Route & Controller | `GET /scout_overview_reports/conversations` on `ScoutOverviewReportsController` | Clean separation from summary metrics; reuse auth filters |
| Metric Aggregation | Scoped query on current page's 25 `conversation_id`s | Avoid computing message stats for non-visible pages |
| Frontend Components | `RecentConversationsSection.vue` + `ConversationStatusBadge.vue` | Reusable design system, `<script setup>`, Tailwind only |
| Localization | Synchronous `en/scout.json` and `pt_BR/scout.json` additions | Repository i18n convention compliance |
