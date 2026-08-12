# Phase 44: Daily Campaign Ad Spend Collection & Consolidation

**Status**: placeholder — pending brainstorm session
**Depends on**: Phase 27 (Facebook Campaign Integration, `docs/kanban/backlog/01-facebook-campaign-integration/spec27.md`) for campaign identifiers/metadata; Phase 26 (WhatsApp/Meta referral attribution, `docs/kanban/ciclo 7/08-whatsapp-referral-attribution/spec26.md`) for the per-opportunity campaign linkage this phase's cost data will eventually be joined against.

## Quick Preview

Goal: collect ad spend figures (impressions cost / budget spent) per campaign on a daily basis
from the ad platform (Meta Marketing API, per Phase 26/27's existing integration direction),
consolidating them over time into the account's own storage — laying the groundwork for a future
cost-per-lead analysis that joins this spend data against the opportunities attributed to each
campaign.

This phase is scoped to **collection and consolidation only** — the actual cost-per-lead analysis
and its presentation is Phase 45 territory (or a further phase), not built here.

Open questions for the brainstorm:
- Data source: Meta Marketing Insights API only, or does this need to account for other ad
  platforms in play (e.g. Google Ads) depending on which channels currently drive WhatsApp/inbound
  leads?
- Ingestion mechanism: a scheduled job (daily cron) pulling per-campaign spend from the platform's
  Insights API — what granularity (campaign level vs. ad-set/ad level), and does it need
  historical backfill on first run or only forward collection?
- Storage shape: a new table (e.g. `campaign_daily_spend` or similar) keyed by account, campaign
  id, and date — raw daily rows, with rollups (weekly/monthly) computed on read or maintained
  separately?
- Rate limits / API quota handling — Phase 26 already designs a rate-limited async resolution job
  against the Meta Marketing API; should this reuse the same client/rate-limiting infrastructure?
- Where does this campaign spend data live relative to the campaign attribution columns Phase 26
  adds to `Opportunity` — same `campaign_id` value space, so a straightforward join key exists?
