# Contract: Campaign Recipients API

Three new, unconditional (no `ChatwootApp.enterprise?` gate) routes nested under the existing
`resources :campaigns` block in `config/routes.rb`, served by
`Api::V1::Accounts::Campaigns::RecipientsController`. All three mirror
`Api::V1::Accounts::Campaigns::AnalyticsController` (Enterprise)'s existing `metrics`/`contacts`
actions in auth, param handling, and response envelope — the only new shape is `reply_breakdown`.

**Authorization** (all three actions): `authorize @campaign, :show?` via the existing, Enterprise-independent
`CampaignPolicy` (`administrator?`). `@campaign = Current.account.campaigns.find_by!(display_id:
params[:campaign_id])`. A `before_action` mirrors the Enterprise controller's
`ensure_whatsapp_campaign_analytics_enabled!` (`@campaign.one_off? && @campaign.inbox.inbox_type ==
'Whatsapp' && Current.account.feature_enabled?(:whatsapp_campaign)`, `raise
Pundit::NotAuthorizedError` otherwise) — same gate, same feature flag, no Enterprise dependency.

## `GET /api/v1/accounts/:account_id/campaigns/:campaign_id/recipients/metrics`

**Response `200`**:

```json
{
  "audience": 250,
  "sent": 248,
  "delivered": 240,
  "read": 190,
  "failed": 2,
  "skipped": 2,
  "replied": 61,
  "status_counts": {
    "queued": 0,
    "skipped": 2,
    "sent": 8,
    "delivered": 50,
    "read": 129,
    "replied": 61,
    "failed": 2
  }
}
```

**Field semantics** (identical to the Enterprise `analytics/metrics` response except `replied`):
- `audience`: `@campaign.ichatr_campaign_recipients.count`.
- `sent`: recipients with `source_id` present (accepted by WhatsApp for delivery — includes ones
  that later moved past `sent` in the lifecycle).
- `delivered`: `status_counts[:delivered] + status_counts[:read]` (delivered-or-further, matching
  Enterprise's own convention exactly).
- `read`, `failed`, `skipped`: raw `status_counts` values.
- `replied` (**new**): count of recipients with `replied_at` present — not the same as
  `status_counts[:replied]`, since a recipient whose status later moved to `failed` (e.g., a
  late-arriving failure webhook after they'd already replied) still counts toward `replied` here.
  Use `replied_at.present?`, not `status == 'replied'`, as the count predicate.
- `status_counts`: one key per enum value, `0` when absent — same shape as Enterprise's, with one
  additional key (`replied`).

## `GET /api/v1/accounts/:account_id/campaigns/:campaign_id/recipients/contacts`

Identical response envelope and pagination to the existing Enterprise `analytics/contacts` (25 per
page, `page` param, `status` param filters by enum value when valid — unchanged, no new filter
value needed since `replied` is already a `status` enum member):

```json
{
  "payload": [
    {
      "contact": { "id": 1, "name": "Jane Doe", "phone_number": "+15551234567" },
      "status": "replied",
      "message_content": "Olá Jane! Temos uma promoção especial...",
      "error_code": null,
      "error_title": null,
      "error_message": null
    }
  ],
  "meta": { "current_page": 1, "total_pages": 4, "total_count": 91 }
}
```

Unchanged from the Enterprise shape (source-shaped table is reused as-is per spec — this is not a
new UI surface, just a repointed data source).

## `GET /api/v1/accounts/:account_id/campaigns/:campaign_id/recipients/reply_breakdown`

New endpoint — no Enterprise equivalent.

**Response `200`**:

```json
[
  { "label": "Sim, quero agendar", "total_clicks": 42, "click_rate": 0.31 },
  { "label": "Falar com atendente", "total_clicks": 18, "click_rate": 0.13 },
  { "label": "other", "total_clicks": 9, "click_rate": 0.07 }
]
```

**Computation**:
- Group `@campaign.ichatr_campaign_recipients.where(reply_type: :quick_reply)` by `reply_label`,
  `count` per group → `total_clicks`.
- Order by `total_clicks` desc.
- Append one trailing row with the **literal machine key** `label: "other"` — not a display
  string, not "Outras respostas" — with `total_clicks =
  @campaign.ichatr_campaign_recipients.where(reply_type: :free_text).count`. **Always present**,
  even when `0`, and always last regardless of its count (not sorted with the rest). The frontend,
  not the backend, owns the "Outras respostas"/"Other replies" copy: `CampaignReplyBreakdown.vue`
  must special-case `label === 'other'` and render it via
  `t('CAMPAIGN.WHATSAPP.ANALYTICS.REPLY_BREAKDOWN.OTHER_REPLIES')` instead of printing the raw
  `label` value directly (unlike every other row, where `label` is `reply_label` and is printed
  as-is) — this is the one row where `label` is a key, not display text, and it participates in
  i18n normally instead of being hardcoded server-side in one language.
- `click_rate = total_clicks.to_f / sent_count` for every row including the "other" row, where
  `sent_count = @campaign.ichatr_campaign_recipients.where.not(source_id: nil).count` (same
  denominator as the `metrics` endpoint's `sent` field). `click_rate: 0.0` when `sent_count` is `0`
  (guards divide-by-zero; only possible before any send has gone out, in which case the page's
  empty state already prevents this endpoint from being called per `WhatsAppCampaignAnalyticsPage.vue`'s
  existing `analyticsEmptyState`/`showAnalytics` gating).

**Response shape rule**: unlike `metrics`/`contacts`, this is a bare array, not wrapped in a
`payload`/`meta` envelope — there is no pagination (bounded by the number of distinct button labels
a campaign template can realistically have, plus the one synthetic row).

## `GET /api/v1/accounts/:account_id/campaigns/:campaign_id/analytics/*` (existing — untouched)

Left exactly as-is, still `if ChatwootApp.enterprise?`-gated, still routing to
`Api::V1::Accounts::Campaigns::AnalyticsController` (Enterprise), still reading/writing the
Enterprise `campaign_recipients` table. Simply has no frontend caller once
`WhatsAppCampaignAnalyticsPage.vue` is repointed. Not part of this contract — documented here only
to make explicit that no change is made to it.
