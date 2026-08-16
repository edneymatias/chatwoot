# Quickstart & Verification Guide: Meta Referral Attribution Refinements

**Feature**: Meta Referral Attribution Refinements  
**Spec Reference**: `specs/037-meta-referral-attribution-refinements/spec.md`  

---

## 1. Prerequisites

- Stack running via Docker Compose (`docker compose up -d`).
- Seed data or existing WhatsApp channel configured.

---

## 2. Automated Test Commands

### Backend Specs (RSpec)
```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/jobs/custom/campaign_resolution_job_spec.rb \
  custom/spec/jobs/meta/attach_campaign_thumbnail_job_spec.rb \
  custom/spec/jobs/meta/drain_pending_attributions_job_spec.rb \
  custom/spec/jobs/meta/pending_attributions_sweeper_job_spec.rb \
  custom/spec/services/custom/automation_rules/action_service_spec.rb \
  custom/spec/services/meta/graph_api_client_spec.rb \
  custom/spec/controllers/api/v1/accounts/campaign_attribution_settings_controller_spec.rb
```

### Frontend Tests (Vitest)
```bash
docker compose exec vite pnpm test app/javascript/dashboard/composables/specs/useOpportunityCardFields.spec.js
```

---

## 3. End-to-End Verification Scenarios

### Scenario 1: Organic Post Referral Processing
1. Simulate an inbound message with organic referral payload (`source_type: "post"`, `headline: "Dica de Vendas"`, `body: "Texto do post"`, `thumbnail_url: "https://example.com/thumb.jpg"`).
2. Verify opportunity created with `campaign_resolution_status: 'organic_post'`, `campaign_headline`, `campaign_body`, and `campaign_thumbnail_url`.
3. Verify that `Custom::CampaignResolutionJob` was **not** enqueued.
4. Verify account `CampaignAttributionSetting` remains `enabled: true`.

### Scenario 2: Isolated Query Failure vs Token Revocation
1. For an opportunity with an unresolvable ad ID returning Meta Graph API error code 100:
   - Run `Custom::CampaignResolutionJob.perform_now(opportunity.id)`.
   - Verify opportunity status becomes `failed`.
   - Verify account setting remains `enabled: true`.
2. For an opportunity where Meta Graph API returns error code 190 (Invalid OAuth token):
   - Run resolution job.
   - Verify opportunity status becomes `failed`.
   - Verify account setting is updated to `enabled: false` and `access_token` is cleared.

### Scenario 3: Popover Thumbnail Preview in Kanban
1. Open the Kanban board (`/app/accounts/{account_id}/opportunities`).
2. Locate a card with resolved attribution or organic post attribution.
3. Hover over the platform icon (`Instagram` / `Facebook` / `Megafone`).
4. Verify popover displays thumbnail preview, headline/campaign details, and human-readable text.

### Scenario 4: Auto-Drain on Reconnection & Settings Button
1. Disconnect Meta integration in Settings → Funis de Vendas → Atribuição de Campanhas.
2. Create 2 opportunities with `campaign_resolution_status: 'pending'`.
3. In Settings, click "Conectar com Facebook" or click "Reprocessar Pendentes".
4. Verify toast notification appears and pending opportunities are resolved in the background.
