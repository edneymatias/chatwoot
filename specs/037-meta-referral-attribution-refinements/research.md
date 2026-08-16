# Research & Technical Decisions: Meta Referral Attribution Refinements

**Feature**: Meta Referral Attribution Refinements  
**Spec Reference**: `specs/037-meta-referral-attribution-refinements/spec.md`  
**Date**: 2026-08-14  

---

## 1. Meta Graph API Error Classification & OAuth Invalidation

### Problem
Meta Graph API returns `"type": "OAuthException"` for almost all HTTP 4xx errors, including:
- Querying an organic Post node with Ad fields (`code: 100`, `message: "(#100) Tried accessing nonexisting field (adset) on node type (Post)"`)
- Querying a deleted/unsupported object ID (`code: 100` or `code: 803`)
- User/app rate limit hits (`code: 17`, `code: 32`, `code: 613`)
- Genuine token revocation / expiry (`code: 190` with subcodes `458`, `460`, `463`, `467`, `490`)

The initial implementation in `Custom::CampaignResolutionJob` caught any `OAuthException` string and wiped the account's `access_token`, disabling attribution account-wide.

### Technical Decision
1. Introduce custom exception classes under `Meta::` in `custom/app/services/meta/exceptions.rb`:
   - `Meta::AuthenticationError < StandardError`: Triggered only on `error.code == 190` (and authentic auth revocation subcodes).
   - `Meta::RateLimitError < StandardError`: Triggered on `error.code.in?([17, 32, 613])` or HTTP 429.
   - `Meta::NodeNotFoundError < StandardError`: Triggered on `error.code == 100` or HTTP 404 (non-existent or mismatched node type).
   - `Meta::ApiError < StandardError`: Generic wrapper for other unexpected API errors.
2. In `Meta::GraphApiClient#fetch_ad_details`:
   - Inspect JSON error structure: `response.parsed_response['error']`.
   - Raise the appropriate typed exception.
3. In `Custom::CampaignResolutionJob`:
   - `rescue Meta::AuthenticationError`: Wipe `access_token` and set `setting.update!(enabled: false)`. Mark opportunity `failed`.
   - `rescue Meta::RateLimitError`: Call `retry_job wait: 2.minutes`. Leave setting and opportunity intact.
   - `rescue Meta::NodeNotFoundError, Meta::ApiError`: Mark only the current opportunity `failed`. Leave account `CampaignAttributionSetting` active (`enabled: true`).

### Alternatives Considered
- *Check only HTTP status codes (e.g. 401)*: Rejected because Meta Graph API returns HTTP 400 with `"type": "OAuthException"` for both code 190 (auth revoked) and code 100 (invalid node query). Parsing the inner `code` and `error_subcode` is mandatory.

---

## 2. Inbound Organic Post Referral Identification & Data Extraction

### Problem
WhatsApp inbound referral webhooks from organic Facebook/Instagram posts or stories supply referral metadata where `source_type == "post"`, `story_fbid`, `video_url`, or post IDs are present without an ad ID. When sent to the marketing ad resolution endpoint, they fail with node type errors and dump raw IDs in the UI.

### Technical Decision
1. In `Custom::AutomationRules::ActionService.process_campaign_attribution`:
   - Inspect `referral['source_type']` and presence of post attributes (`story_fbid`, `video_url`, `headline`, `body`).
   - If `source_type == 'post'` or if an organic signature is detected:
     - Set `campaign_resolution_status = 'organic_post'`.
     - Extract `campaign_headline = referral['headline']`.
     - Extract `campaign_body = referral['body']`.
     - Extract `campaign_thumbnail_url = referral['thumbnail_url'] || referral['image_url'] || referral['video_url']`.
     - Dispatch `Meta::AttachCampaignThumbnailJob` if a thumbnail URL is present.
     - **Skip** enqueueing `Custom::CampaignResolutionJob` entirely.
2. For paid ads:
   - Set `campaign_resolution_status = 'pending'`.
   - Enqueue `Custom::CampaignResolutionJob`. When resolved, also enqueue `Meta::AttachCampaignThumbnailJob` if `creative.thumbnail_url` or `image_url` is returned by Graph API.

### Alternatives Considered
- *Query Meta Graph API `/v22.0/{post_id}` for organic posts*: Rejected because organic post endpoints require different permissions (`pages_read_user_content`, `instagram_basic`) rather than `ads_read`, and the webhook referral payload already provides the required headline, body, and thumbnail directly.

---

## 3. Creative Media & Thumbnail Expiration Handling

### Problem
Meta CDN URLs (`scontent...fbcdn.net`) contain signed query parameters (`oh` and `oe`) that expire after 30–60 days, causing broken image previews on older Kanban cards.

### Technical Decision
1. Persist the initial CDN string in `Opportunity#campaign_thumbnail_url`.
2. Define `has_one_attached :campaign_thumbnail` on `Opportunity`.
3. In `Meta::AttachCampaignThumbnailJob`:
   - Download the image stream via `Down` / `URI.open` with timeouts (3 seconds open, 5 seconds read, 5MB max).
   - Attach to `opportunity.campaign_thumbnail` with appropriate content type (`image/jpeg`, `image/png`).
   - On network failure or expired image, log warning and exit cleanly (graceful fallback to CDN URL or text-only display).
4. Opportunity serializer / API responses:
   - `campaign_thumbnail_url`: Returns Rails ActiveStorage blob URL (`Rails.application.routes.url_helpers.rails_blob_url(opportunity.campaign_thumbnail)`) if attached, falling back to the stored `campaign_thumbnail_url` CDN string.

### Alternatives Considered
- *Live image proxy endpoint*: Rejected because it adds backend request latency on every board load and fails if the upstream CDN URL has expired.

---

## 4. Kanban Card Surface & Attribution Popover Design

### Problem
Cards on the Kanban board need to remain clean, compact, and scannable without differing card heights caused by large image cover banners.

### Technical Decision
1. **Card Face**:
   - Maintain text-first compact layout.
   - Display the platform icon (`i-lucide-instagram` / `i-lucide-facebook` / `i-lucide-megaphone`) next to the opportunity title.
2. **Attribution Popover**:
   - Triggered on hover/click over the attribution icon.
   - Renders a floating popover card containing:
     - Header: "Publicação Orgânica" (for organic) or "Atribuição de Anúncio" (for paid ads).
     - Thumbnail: 48x48 rounded preview image with zoom on click.
     - Details:
       - Paid Ad: Campaign Name, Ad Set Name, Ad Name.
       - Organic Post: Platform, Headline, Body snippet, Post URL/ID.
       - Failed: Clear human-readable failure explanation (*"Não foi possível identificar o anúncio ou publicação (ID: {id})"*) instead of raw numeric ID.

---

## 5. Auto-Drain, Scheduled Sweeper & Throttling

### Problem
Opportunities created during disconnection stay in `pending` status indefinitely with no automated recovery path.

### Technical Decision
1. **Auto-Drain Job (`Meta::DrainPendingAttributionsJob`)**:
   - Triggered on `CampaignAttributionSettingsController#connect` and `#update(enabled: true)`.
   - Fetches pending opportunities for the account: `account.opportunities.where(campaign_resolution_status: 'pending')`.
   - Enqueues `Custom::CampaignResolutionJob` in batches with incremental delays (e.g. 10 jobs/second) to prevent burst rate limit exhaustion.
2. **Periodic Sweeper Job (`Meta::PendingAttributionsSweeperJob`)**:
   - Runs every 1 hour via Sidekiq-cron.
   - Queries enabled accounts with pending opportunities created > 15 minutes ago.
   - Enqueues `DrainPendingAttributionsJob` for those accounts.
3. **Manual Reprocess Endpoint**:
   - `POST /api/v1/accounts/:account_id/campaign_attribution_settings/reprocess_pending`.
   - Returns JSON with count of queued opportunities and success message.
