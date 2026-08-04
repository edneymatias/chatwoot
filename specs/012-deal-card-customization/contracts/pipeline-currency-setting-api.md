# API Contract: Pipeline Currency Setting

Base path: `/api/v1/accounts/:account_id/pipeline_currency_setting` (singular resource — no `:id`,
one row per account)

Authorization: account administrator only, matching `PipelineCardFieldConfigPolicy`/
`PipelineClosingRequiredFieldPolicy`.

## `GET /` (show)

Returns the account's current currency, defaulting to `usd` if never explicitly set (without
persisting a row until the admin actually saves a change).

**Response `200`**:
```json
{ "currency": "usd" }
```

## `PATCH/PUT /` (update)

**Request**:
```json
{ "currency": "brl" }
```

**Response `200`**: the updated setting (same shape as show).

**Response `422`** when `currency` is not one of the supported codes (`usd`, `brl`):
```json
{ "error": "<validation message>" }
```

## Consumers

- This phase: `KanbanCard.vue` badge for the `deal_value` field type and for any custom attribute
  with `attribute_display_type: 'currency'`, via `formatCurrencyAmount` from
  `app/javascript/dashboard/constants/pipelineCurrency.js`.
- Future (not built in this phase): pipeline-totals header, reports — expected to read the same
  setting when implemented.
