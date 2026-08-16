# Phase 46: Meta Referral Attribution Refinements — Organic Post Handling, Ad Creative Thumbnails, Robust OAuth Error Handling & Auto-Recovery

**Status**: Approved / Ready for implementation  
**Depends on**: Phase 26 (`docs/kanban/ciclo 7/08-whatsapp-referral-attribution/spec26.md`) / Spec 031 (WhatsApp Referral Attribution via Meta Marketing API)

---

## 1. Context & Motivation

Phase 26 / Spec 031 introduced Click-to-WhatsApp campaign referral capture, async resolution of campaign/ad-set/ad names via Meta Graph API, and visual attribution badges on Opportunity cards.

Initial production usage revealed four critical areas requiring structural refinement:

1. **False-Positive Account Disconnections on Organic Posts**:
   - Meta Graph API returns `"type": "OAuthException"` for almost all query errors, including `code: 100` (e.g., querying an organic Page Post or Story ID with ad-specific fields like `adset` or `campaign`).
   - The initial resolution job caught any `"OAuthException"` and treated it as a permanent token revocation, wiping `access_token` and setting `enabled: false` on the account's `CampaignAttributionSetting`.
   - This caused subsequent real ad opportunities to remain stuck in `pending` indefinitely.
2. **Lack of Distinction Between Ads and Organic Posts in Kanban**:
   - Inbound WhatsApp referral payloads can originate from organic Facebook/Instagram posts, stories, or profile links (`source_type: "post"`, `source_id: "<post_id>"`).
   - These failed Graph API ad resolution and fell back to displaying a raw numeric ID (e.g. `1587983499577672`) in the card tooltip without identifying that the lead came from an organic post.
3. **Card Visual Enrichment: Ad Creative Preview / Thumbnail**:
   - The WhatsApp referral payload delivers `thumbnail_url`, `image_url`, or `video_url` directly on the incoming message's `content_attributes['referral']`.
   - Graph API resolution also returns creative references (`creative.effective_object_story_id`, `object_story_spec`, `thumbnail_url`).
   - Having a thumbnail preview in the attribution popover provides agents with immediate visual context without cluttering the Kanban card face.
4. **Orphaned `pending` Opportunities During Disconnections / Downtime**:
   - Opportunities created while the Meta integration is temporarily disabled or disconnected receive `campaign_resolution_status: 'pending'`, but the resolution job is skipped.
   - When an administrator reconnects the integration, there was no automatic sweeper or trigger to process those backlog `pending` opportunities.

---

## 2. Architecture & Detailed Design Decisions

### 2.1 Data Model Changes (`Opportunity`)

Add dedicated columns to `ichatr_opportunities` table to store organic post text, creative media references, and status:

- `campaign_headline` (`string`): Post headline or ad headline captured from referral payload or Graph API.
- `campaign_body` (`text`): Post body or ad copy text.
- `campaign_thumbnail_url` (`text`): Initial CDN image/thumbnail URL.
- `has_one_attached :campaign_thumbnail`: ActiveStorage attachment to cache creative images locally/S3, preventing image expiration when Meta CDN signed URLs (`oh`/`oe` query parameters) expire after 30–60 days.
- `campaign_resolution_status` values:
  - `'pending'`: Awaiting async Graph API resolution.
  - `'resolved'`: Successfully resolved via Meta Marketing API.
  - `'organic_post'`: Identified as an organic Facebook/Instagram post or story.
  - `'failed'`: Resolution attempted but failed (invalid node, deleted ad, unresolvable ID).
  - `'not_applicable'`: No referral or campaign data present on lead creation.

```ruby
class AddAttributionRefinementsToIchatrOpportunities < ActiveRecord::Migration[7.0]
  def change
    add_column :ichatr_opportunities, :campaign_headline, :string
    add_column :ichatr_opportunities, :campaign_body, :text
    add_column :ichatr_opportunities, :campaign_thumbnail_url, :text
  end
end
```

---

### 2.2 Robust OAuth & Graph API Error Classification

Define explicit exception classes under `Meta::` to accurately classify Graph API errors:

```
Meta::Error (StandardError)
├── Meta::AuthenticationError (code 190, subcodes 458, 460, 463, 467, 490) -> Disconnects integration
├── Meta::RateLimitError (codes 17, 32, 613, or HTTP 429) -> Retries job with exponential backoff
├── Meta::NodeNotFoundError (code 100, 404, or invalid object type) -> Fails only the specific opportunity
└── Meta::ApiError (generic 4xx/5xx API failures) -> Logs error, marks opportunity as failed
```

#### Resolution Behavior by Error Type:
1. **`Meta::AuthenticationError`**:
   - Only triggered when Meta explicitly rejects the token (revoked, expired, password changed, app deauthorized).
   - Wipes `access_token` from `provider_config` and updates `setting.update!(enabled: false)`.
   - Marks current opportunity `campaign_resolution_status = 'failed'`.
   - Emits a diagnostic log entry.
2. **`Meta::RateLimitError`**:
   - Triggers Sidekiq retry: `retry_job wait: 2.minutes`.
   - Does **not** disconnect the account and does **not** fail the opportunity.
3. **`Meta::NodeNotFoundError` / `Meta::ApiError`**:
   - Marks the individual opportunity `campaign_resolution_status = 'failed'`.
   - Leaves account's `CampaignAttributionSetting` intact (`enabled: true`).

---

### 2.3 Organic Post Identification Pipeline

In `Custom::AutomationRules::ActionService.process_campaign_attribution`:

1. Inspect incoming message's `content_attributes['referral']`:
   - Check if `source_type == 'post'` or if organic post identifiers are present (`video_url`, `story_fbid`, or missing ad identifier).
2. For organic posts:
   - Extract `headline = referral['headline']`, `body = referral['body']`, and `thumbnail_url = referral['thumbnail_url'] || referral['image_url'] || referral['video_url']`.
   - Update opportunity with `campaign_headline`, `campaign_body`, `campaign_thumbnail_url`, and `campaign_resolution_status: 'organic_post'`.
   - Asynchronously enqueue `Meta::AttachCampaignThumbnailJob` if `thumbnail_url` is present to download and attach to ActiveStorage.
   - **Skip** enqueueing `Custom::CampaignResolutionJob` to prevent querying ad endpoints and conserve API quota.
3. For paid ads:
   - Save initial referral metadata and set `campaign_resolution_status = 'pending'`.
   - Enqueue `Custom::CampaignResolutionJob`.

---

### 2.4 Creative Media & Thumbnail Handling

1. **Storage & Fallback**:
   - CDN URL is saved in `campaign_thumbnail_url`.
   - `Meta::AttachCampaignThumbnailJob` downloads the image and attaches it to `opportunity.campaign_thumbnail` via ActiveStorage.
   - If download fails or image is not accessible, job fails gracefully without affecting attribution data.
2. **API Exposure**:
   - Opportunity serializer exposes `campaign_thumbnail_url` (returning ActiveStorage blob URL if attached, falling back to `campaign_thumbnail_url` string).

---

### 2.5 Kanban Card UI & Attribution Popover Design

1. **Card Face (Clean & Text-Only)**:
   - The card surface remains sleek and compact without heavy image cover banners.
   - Distinct icons next to the opportunity title:
     - Paid Ad & Organic Post: Origin platform icon (`i-lucide-facebook` / `i-lucide-instagram` / `i-lucide-megaphone`).
     - Pending: Subtle spinning/loading icon or badge.
     - Failed: Warning/alert icon with fallback.
2. **Attribution Popover / Tooltip**:
   - On hover/click of the attribution icon, a rich popover appears containing:
     - **For Paid Ads**: Campaign name, Ad Set name, Ad name, and Creative Thumbnail preview (if available).
     - **For Organic Posts**: "Publicação Orgânica", Platform (Instagram/Facebook), Post Headline/Body snippet, Post URL/ID, and Creative Thumbnail preview (if available).
     - **For Failed Attribution**: Clear human-readable explanation (*"Não foi possível identificar o anúncio ou publicação (ID: {id})"*) instead of raw numeric ID alone.

---

### 2.6 Auto-Drain, Scheduled Sweeper & Manual Reprocess Controls

1. **Auto-Drain on Reconnection / Enablement**:
   - When `CampaignAttributionSettingsController#connect` or `#update(enabled: true)` succeeds, enqueue `Meta::DrainPendingAttributionsJob.perform_later(account.id)`.
   - `DrainPendingAttributionsJob` queries all opportunities in `account.opportunities.where(campaign_resolution_status: 'pending')` and enqueues resolution with batching/spacing to respect `Meta::RateLimiter`.
2. **Recurring Sweeper**:
   - Sidekiq-cron job `Meta::PendingAttributionsSweeperJob` runs hourly.
   - Sweeps across enabled accounts for opportunities with `campaign_resolution_status: 'pending'` created older than 15 minutes and enqueues their resolution.
3. **Manual Reprocess in Settings**:
   - Backend endpoint: `POST /api/v1/accounts/:account_id/campaign_attribution_settings/reprocess_pending`.
   - Enqueues `DrainPendingAttributionsJob` and returns the count of queued opportunities.
   - In `CampaignAttributionSettings.vue`, display a "Reprocessar Pendentes" button showing the number of currently pending opportunities with toast notification feedback.

---

## 3. API & Controller Specifications

### 3.1 `CampaignAttributionSettingsController`

```ruby
# POST /api/v1/accounts/:account_id/campaign_attribution_settings/reprocess_pending
def reprocess_pending
  count = current_account.opportunities.where(campaign_resolution_status: 'pending').count
  if count > 0 && setting&.enabled? && setting.provider_config['access_token'].present?
    Meta::DrainPendingAttributionsJob.perform_later(current_account.id)
    render json: { message: I18n.t('campaign_attribution.reprocess_enqueued', count: count), count: count }
  else
    render json: { message: I18n.t('campaign_attribution.no_pending_or_disabled'), count: count }
  end
end
```

### 3.2 Response Payloads

`GET /api/v1/accounts/:account_id/campaign_attribution_settings` includes:
```json
{
  "enabled": true,
  "connected": true,
  "pending_count": 5,
  "meta_app_id": "...",
  "meta_api_version": "v22.0"
}
```

---

## 4. Internationalization (i18n)

Synchronous updates across backend (`en.yml`, `pt_BR.yml`) and frontend (`en.json`, `pt_BR.json`):

### Frontend Keys (`OPPORTUNITIES.CAMPAIGN.*` & `PIPELINE_STAGES_MGMT.CAMPAIGN_ATTRIBUTION.*`):
- `OPPORTUNITIES.CAMPAIGN.ORGANIC_POST`: "Organic Post" / "Publicação Orgânica"
- `OPPORTUNITIES.CAMPAIGN.FAILED_TOOLTIP`: "Unable to identify ad or post details (ID: {id})" / "Não foi possível identificar os detalhes do anúncio ou publicação (ID: {id})"
- `OPPORTUNITIES.CAMPAIGN.POPUP_TITLE_PAID`: "Ad Attribution" / "Atribuição de Anúncio"
- `OPPORTUNITIES.CAMPAIGN.POPUP_TITLE_ORGANIC`: "Organic Attribution" / "Atribuição Orgânica"
- `PIPELINE_STAGES_MGMT.CAMPAIGN_ATTRIBUTION.REPROCESS_BUTTON`: "Reprocess Pending" / "Reprocessar Pendentes"
- `PIPELINE_STAGES_MGMT.CAMPAIGN_ATTRIBUTION.REPROCESS_SUCCESS`: "{count} pending opportunities queued for resolution." / "{count} oportunidades pendentes enviadas para resolução."

---

## 5. Acceptance Criteria

1. **Organic Post Resiliency**:
   - An incoming lead from an organic Facebook/Instagram post or story is classified as `campaign_resolution_status: 'organic_post'`.
   - Post headline, body snippet, and thumbnail are extracted and stored.
   - The Meta integration remains `connected: true` and `enabled: true`.
2. **OAuth Error Accuracy**:
   - Account disconnection only occurs when Meta returns authentic token invalidation (`code: 190`).
   - Query errors (`code: 100`, 404, invalid node) fail only the affected opportunity, without clearing tokens.
   - Rate limit errors (`code: 17/32/613` or HTTP 429) automatically trigger job retries.
3. **Visual Card Enrichment**:
   - Organic posts display the origin platform icon (Instagram/Facebook) with tooltip/popover detailing "Publicação Orgânica".
   - Hovering over attribution badges displays a rich popover containing creative thumbnail and complete metadata.
   - Failed attributions display clear human-readable explanations instead of raw numeric IDs.
4. **Auto-Recovery & Drainage**:
   - Reconnecting or re-enabling the integration automatically drains pending opportunities.
   - An hourly Sidekiq sweeper resolves any orphaned pending opportunities older than 15 minutes.
   - Administrators can trigger manual reprocessing directly from the Campaign Attribution settings screen.
