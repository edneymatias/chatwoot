# Contract: Background Jobs & Async Processing

## 1. `Custom::CampaignResolutionJob`
- **Queue**: `low`
- **Arguments**: `(opportunity_id)`
- **Behavior**:
  - Validates `opportunity.campaign_resolution_status == 'pending'`.
  - Checks `Meta::RateLimiter`.
  - Queries `Meta::GraphApiClient#fetch_ad_details(opportunity.campaign_source_id)`.
  - On success: updates opportunity with names, headline, body, thumbnail URL, and sets `campaign_resolution_status = 'resolved'`. Enqueues `Meta::AttachCampaignThumbnailJob`.
  - On `Meta::AuthenticationError`: sets status `failed`, deletes access token, sets `setting.update!(enabled: false)`.
  - On `Meta::RateLimitError`: calls `retry_job wait: 2.minutes`.
  - On `Meta::NodeNotFoundError` / `Meta::ApiError`: sets status `failed`, leaves setting enabled.

---

## 2. `Meta::AttachCampaignThumbnailJob`
- **Queue**: `low`
- **Arguments**: `(opportunity_id, thumbnail_url)`
- **Behavior**:
  - Downloads image stream with 5s timeout and 5MB max size.
  - Attaches blob to `opportunity.campaign_thumbnail`.
  - Tolerates 404 / 403 / network timeouts gracefully without raising or altering attribution status.

---

## 3. `Meta::DrainPendingAttributionsJob`
- **Queue**: `low`
- **Arguments**: `(account_id)`
- **Behavior**:
  - Finds all opportunities in `account.opportunities.where(campaign_resolution_status: 'pending')`.
  - Enqueues `Custom::CampaignResolutionJob` in batches with incremental delays (e.g. 10 jobs/second) to prevent burst load on Meta Graph API and Redis.

---

## 4. `Meta::PendingAttributionsSweeperJob`
- **Schedule**: Periodic (Hourly via Sidekiq-cron)
- **Behavior**:
  - Finds all accounts where `campaign_attribution_setting.enabled == true`.
  - For each account, checks if there are opportunities in `pending` created older than 15 minutes.
  - Enqueues `Meta::DrainPendingAttributionsJob.perform_later(account.id)`.
