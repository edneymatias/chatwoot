# Contract: `GET /api/v1/accounts/{account_id}/opportunities` — extended `q`/`payload` semantics

Controller: `custom/app/controllers/api/v1/accounts/opportunities_controller.rb` (unchanged file —
only the shared `OpportunitiesFilter` finder it calls is modified). No route, param name, or
response shape changes; this documents the *widened* matching semantics of two existing params.

## `q` (free-text search) — extended

**Before**: matches `title` (ILIKE) or `contacts.name` (ILIKE).

**After**: also matches `campaign_name`, `campaign_adset_name`, `campaign_ad_name`,
`campaign_platform` (all ILIKE, case-insensitive partial match). An opportunity matches if **any**
of the six fields contains the search term.

## `payload` (advanced filter conditions) — new attribute keys accepted

Each condition is `{ "attribute_key": ..., "filter_operator": ..., "values": [...] }` (unchanged
shape). Newly meaningful `attribute_key` values, all standard `Opportunity` columns (routed through
`apply_standard_column_filter`, not the custom-attributes path):

| `attribute_key` | Accepted `filter_operator` values | Notes |
|---|---|---|
| `campaign_name` | `contains`, `does_not_contain` (also `equal_to`/`not_equal_to`, inherited generically) | NEW operator support: `contains`/`does_not_contain`. |
| `campaign_adset_name` | same as above | |
| `campaign_ad_name` | same as above | |
| `campaign_platform` | `equal_to`, `not_equal_to` | Values constrained by the frontend dropdown to `facebook`/`instagram`; backend does not validate against an enum (plain string column). |
| `created_at` | `is_greater_than`, `is_less_than`, `days_before` (also `equal_to`/`not_equal_to`, inherited generically) | No backend change — generic standard-column handling already supports any column name. |
| `updated_at` | same as `created_at` | |

`contains`/`does_not_contain` semantics: case-insensitive partial match (ILIKE `%value%`), applied
via `OR` across all supplied `values` for `contains`, and negated (`NOT ... OR ... IS NULL`-safe)
for `does_not_contain` — consistent with core's `FilterService` operator semantics for the same
operator names (`app/services/filter_service.rb:29-31`).

## Behavioral contract

- No existing `attribute_key`/operator combination changes behavior.
- Opportunities with a blank campaign attribution field simply do not match a search/filter
  against that field (no error, no special-casing) — same as any other blank column today.
