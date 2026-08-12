# Quickstart: Validating WhatsApp Referral Attribution

Prerequisites: dev stack running (`docker compose up -d`), a seeded account with at least one
Pipeline Stage and one Automation Rule using the `create_opportunity` action on the
`message_created` trigger (see `Seeders::AccountSeeder` / `rails db:seed` per `CLAUDE.md`).

## 0. One-time prerequisite (Super Admin)

1. Log in to Super Admin.
2. Navigate to the App Configs screen's new "Meta Marketing" section and set
   `META_MARKETING_APP_ID`, `META_MARKETING_APP_SECRET`, and (optionally) `META_MARKETING_API_VERSION`
   for a Meta App with Marketing API access — a one-time, instance-wide setup step, independent of
   the existing WhatsApp App config. Every Chatwoot account's OAuth consent (step 1 below) is
   performed against this shared App.

## 1. Enable the feature (Account Administrator)

1. Log in as an Account Administrator.
2. Navigate to the Pipeline settings screen (`pipelineStages/Index.vue`), Card Fields tab.
3. Click the new "Connect Meta" action — this opens a Facebook login popup (`FB.login`, `ads_read`
   scope) using the Super-Admin-configured App from step 0. Approve the requested ad-data access
   with your own Facebook account; the popup returns an authorization code that the frontend posts
   to the backend for exchange — see `contracts/campaign-attribution-settings-api.md` for the
   underlying API contract.
4. Toggle "Ativar rastreio de campanhas do Meta" on.
5. Verify: `GET /api/v1/accounts/:account_id/campaign_attribution_setting` returns
   `{ "enabled": true, "connected": true }`.

## 2. Trigger synchronous capture (User Story 1, scenarios 1 & 4)

1. Set up (or reuse) an Automation Rule with the `campaign_referral_present` condition (`equal_to
   true`) and the `create_opportunity` action, on the `message_created` trigger.
2. Send an inbound WhatsApp message carrying `content_attributes.referral` (either via a real
   CTWA test send through Ads Manager's Ad Preview tool, per the source design's documented
   testing method, or by seeding a message with that content directly in a dev/test environment).
3. Verify: an Opportunity is created; `campaign_source_id`/`campaign_source_url` are populated;
   `campaign_platform` is set if `source_url` was present; `campaign_resolution_status ==
   'pending'`.
4. Verify (no-referral control case): send a plain inbound message with no `referral` data through
   the same rule — no Opportunity attribution fields are populated, and
   `campaign_resolution_status == 'not_applicable'`.

## 3. Verify async resolution + realtime update (User Story 1, scenarios 2 & 3)

1. Watch the Opportunity card on the Kanban board (`ContactOpportunityCard.vue`) for the
   Opportunity created in step 2, without reloading the page.
2. Confirm the low-priority Sidekiq queue processes the resolution job
   (`docker compose logs -f sidekiq`).
3. Verify: on success, the card updates live to show `campaign_name`/`campaign_adset_name`/
   `campaign_ad_name` and `campaign_resolution_status` becomes `resolved` — confirm via the
   `opportunity_updated` ActionCable event payload (see
   `contracts/opportunity-updated-event.md`).
4. Verify the cache: create a second Opportunity referencing the same `campaign_source_id` within
   12 hours — confirm (via Sidekiq job logs or a Redis `GET` on the cache key) that no second Meta
   Graph API call is made and the second Opportunity resolves immediately from the cache.
5. Force a terminal failure (e.g. point at a deleted/invalid ad id) and verify
   `campaign_resolution_status` becomes `failed`, with `campaign_source_id`/`campaign_platform`
   still visible on the card as a fallback.

## 4. Verify the automation condition survives text edits (User Story 2)

1. Using the real Ads Manager Ad Preview flow (not scripted clicks — see spec Constraints), send
   three test messages against the same rule from step 2's setup: (a) unedited suggested text, (b)
   edited text, (c) fully replaced text.
2. Verify: all three create an Opportunity via the `campaign_referral_present` condition,
   regardless of the message body.

## 5. Run the backfill (User Story 3)

1. Identify a small set of pre-existing Opportunities (from before this feature shipped) whose
   origin conversation's first inbound message carries `referral` data.
2. Run: `docker compose exec rails bundle exec rake campaign_attribution:backfill`.
3. Verify: those Opportunities now have `campaign_resolution_status: pending`, and the resolution
   job runs for each (eventually reaching `resolved`/`failed`).
4. Re-run the same rake task immediately — verify the log output shows those same Opportunities
   now skipped (already processed), not reprocessed.
5. Verify an Opportunity belonging to an account with the toggle off is skipped and counted as
   gated in the task's final summary output.

## Success criteria checklist

- [ ] SC-001: platform indicator visible on the card within 1s of creation (no loading spinner for
  that field specifically).
- [ ] SC-002: ≥95% of eligible test Opportunities show resolved names within 10 minutes.
- [ ] SC-003: 100% of referral-sourced Opportunities show at least a platform indicator, even
  pending/failed.
- [ ] SC-004: backfill run against a realistic batch does not trigger Meta rate-limit errors.
- [ ] SC-005: automation condition fires on 100% of edited/replaced-text test sends.
- [ ] SC-006: Opportunity creation latency is unaffected by resolution (job is fully async).
