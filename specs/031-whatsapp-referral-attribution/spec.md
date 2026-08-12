# Feature Specification: WhatsApp Referral (Facebook/Instagram Ad) Attribution

**Feature Branch**: `031-whatsapp-referral-attribution`

**Created**: 2026-08-11

**Status**: Draft

**Input**: User description: Phase 26 design doc (`docs/kanban/ciclo 7/08-whatsapp-referral-attribution/spec26.md`) — Part 1 (Evolution API referral-data patch) is already resolved and validated in production. Part 2, approved by the user on 2026-08-11, defines the attribution feature to build on top of that data: fixed campaign-attribution columns on the Opportunity, a background job resolving human-readable campaign/ad-set/ad names via the Meta Marketing API, a live UI update once resolved, a boolean automation condition to trigger opportunity creation from campaign messages, and a one-time backfill for opportunities that already exist in production. Target: MVP shippable by the end of the current week.

## Clarifications

### Session 2026-08-11

- Q: Who is allowed to configure the master toggle and the Meta campaign-data connection? → A: Account Administrators only, matching the existing pattern for account-wide integration settings. The user also noted this configuration conceptually belongs with pipeline/card setup (the tab that may later be generalized into "CRM setup"), since the resolved campaign data surfaces on the Opportunity card — recorded as a placement preference, not a hard requirement.
- Q: Should resolution work be deduplicated when many Opportunities share the same campaign source id? → A: Yes — resolved campaign/ad-set/ad names are cached per `campaign_source_id` with a 12-hour TTL. Opportunities resolving against a cached, unexpired entry reuse it without a new Meta API call; once the TTL expires, the next resolution re-queries Meta and refreshes the cache, which also lets renamed campaigns/ad sets/ads eventually surface with their updated names.
- Q: What happens when referral data is missing `source_url` (so platform can't be derived synchronously) but `source_id` is present? → A: Still captured as campaign-sourced with platform left unset at creation time; the async resolution job (already calling the Graph API for name/ad-set/campaign) also derives platform from the ad's creative data as part of that same call and fills it in once resolved — no separate API round trip added.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See campaign origin on an Opportunity card (Priority: P1)

A sales agent working the Kanban board opens or scans the board and, for any Opportunity that originated from a Click-to-WhatsApp ad conversation, can immediately see which platform (Facebook or Instagram) it came from, and — once resolved — which campaign, ad set, and ad drove it, without leaving the board or asking the marketing agency.

**Why this priority**: This is the core value of the whole feature — turning an invisible signal into something agents and managers can act on daily (e.g. prioritizing leads from a known high-performing campaign, or flagging that a specific ad is producing junk leads). Without this, the rest of the feature has no visible outcome.

**Independent Test**: Can be fully tested by sending a real or simulated CTWA WhatsApp message (with `referral` data present) into either the Cloud API or Evolution API inbox, letting the existing `create_opportunity` automation create an Opportunity from it, and confirming the platform indicator appears immediately on the card and the campaign/ad-set/ad name appears after resolution completes.

**Acceptance Scenarios**:

1. **Given** an inbound WhatsApp message carrying campaign referral data triggers the `create_opportunity` automation, **When** the Opportunity is created, **Then** the card immediately shows the originating platform (Facebook or Instagram), even before campaign/ad-set/ad names are resolved.
2. **Given** an Opportunity was created from a campaign message and the master toggle plus Meta authentication are configured, **When** the background resolution completes successfully, **Then** the card updates live (without a manual page refresh) to show the campaign, ad set, and ad names.
3. **Given** an Opportunity was created from a campaign message but resolution ultimately fails (e.g. the ad was deleted, or credentials were revoked), **When** an agent views the card, **Then** it shows the platform and raw campaign identifier as a fallback instead of showing nothing.
4. **Given** an Opportunity was created from a conversation with no campaign referral data at all, **When** an agent views the card, **Then** no campaign attribution indicator is shown.

---

### User Story 2 - Trigger opportunity creation reliably from campaign leads (Priority: P2)

An automation administrator sets up (or already has) an Automation Rule that creates an Opportunity when a new conversation starts from a WhatsApp ad campaign. Instead of matching on the fragile, editable suggested-message text, the administrator can condition the rule on the reliable presence of campaign referral data on the triggering message.

**Why this priority**: This closes the original reliability gap that motivated the whole investigation (leads editing/deleting the suggested text broke text-matching automations) and is what makes User Story 1's data show up on new Opportunities in the first place going forward. It ships after User Story 1 because the display value can be demonstrated with manually/directly created test Opportunities first, but the automation condition is what makes the feature self-sustaining in daily use.

**Independent Test**: Can be fully tested by creating an Automation Rule with the new "campaign message" condition, sending a real or simulated CTWA WhatsApp message with the suggested text edited or fully replaced, and confirming the rule still fires and creates the Opportunity.

**Acceptance Scenarios**:

1. **Given** an Automation Rule configured with the new campaign-message condition, **When** a WhatsApp message carrying campaign referral data arrives (regardless of whether its visible text matches any pre-filled suggestion), **Then** the rule's condition evaluates true and the configured action (e.g. Opportunity creation) fires.
2. **Given** the same Automation Rule, **When** a WhatsApp message with no campaign referral data arrives, **Then** the condition evaluates false and does not fire on that basis.
3. **Given** an administrator is configuring an Automation Rule, **When** they browse available conditions for the message-created trigger, **Then** they see the new campaign-message condition listed alongside existing conditions, labeled in their configured language.

---

### User Story 3 - Backfill attribution on existing production opportunities (Priority: P3)

An administrator, after the feature ships and campaign tracking is enabled, runs a one-time operation to populate attribution data on Opportunities that were already created before this feature existed, so historical reporting and campaign performance review isn't permanently missing data for those records.

**Why this priority**: Valuable for completeness and historical reporting, but strictly dependent on User Stories 1 and 2 already existing (the data columns, the resolution job) and is a one-time administrative action rather than an ongoing user-facing capability — the lowest-risk piece to ship last within the week if time is tight.

**Independent Test**: Can be fully tested by running the backfill operation against a set of pre-existing Opportunities (some with recoverable campaign referral data on their origin conversation, some without, some belonging to accounts with the feature disabled), and confirming each is handled according to its case without needing to touch new-Opportunity creation flows.

**Acceptance Scenarios**:

1. **Given** an existing Opportunity whose origin conversation's first inbound message carries campaign referral data, **When** the backfill operation runs, **Then** the Opportunity's synchronous attribution fields are populated and resolution is queued the same way as for a newly created Opportunity.
2. **Given** an existing Opportunity with no recoverable campaign referral data, **When** the backfill operation runs, **Then** it is left with no attribution data and is not treated as an error.
3. **Given** an existing Opportunity belonging to an account where the feature's master toggle is not enabled, **When** the backfill operation runs, **Then** that Opportunity is skipped.
4. **Given** the backfill operation is interrupted partway through and re-run, **When** it processes the same data set again, **Then** already-processed Opportunities are not reprocessed or duplicated.
5. **Given** the backfill operation completes, **When** the administrator reviews its output, **Then** they can see a count of how many Opportunities were processed, skipped for lacking referral data, and skipped for being gated by account configuration.

---

### Edge Cases

- What happens when a lead edits or completely replaces the suggested opening message text before sending? Campaign referral data still arrives intact and attribution still works — validated empirically in production on both WhatsApp numbers (see Part 1 investigation).
- What happens when the lead deletes their message after sending it? The campaign referral data attached to that message is lost, since Chatwoot's message-deletion behavior overwrites message content. This is an accepted residual risk shared by both WhatsApp paths, not something actively designed around, and no occurrence has been observed in production.
- What happens when resolution of campaign/ad-set/ad names fails permanently (e.g. the ad or campaign was deleted upstream, or the Meta authentication was revoked)? The Opportunity keeps showing its platform and raw campaign identifier rather than showing nothing.
- What happens when the master toggle is off or Meta authentication isn't configured at the moment an Opportunity is created from a campaign message? The immediately-available fields (platform, raw identifiers) are still captured; only the name-resolution step waits until the toggle/auth are enabled (via a later resolution attempt or the backfill operation).
- What happens when an account has never connected any WhatsApp ad campaign source? No campaign attribution indicator appears on any of that account's Opportunity cards, and the feature is otherwise invisible to them.
- What happens when referral data is present but lacks a usable source URL (so platform cannot be derived synchronously)? The Opportunity is still captured as campaign-sourced (raw source id present, resolution status `pending`); platform is left unset until the async resolution job derives it from the ad's creative data.
- What happens when two Opportunities are created from messages referencing the same campaign source id within the 12-hour cache window? The second resolution reuses the cached campaign/ad-set/ad names (and platform, if previously resolved) without issuing a new external API call.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST capture, at the moment an Opportunity is created from a triggering message, the raw campaign source identifier, source URL, and originating platform (Facebook or Instagram) whenever that triggering message carries campaign referral data — independent of whether campaign-name resolution is enabled or configured.
- **FR-002**: System MUST derive the originating platform as Instagram when the campaign source URL indicates an Instagram origin, and Facebook otherwise. When the triggering message's referral data lacks a usable source URL, platform MUST be left unset at capture time rather than guessed, and MUST instead be derived asynchronously by the resolution job (FR-003) from the ad's creative data as part of that same resolution call.
- **FR-003**: System MUST resolve the raw campaign source identifier into human-readable campaign, ad-set, and ad names asynchronously, without blocking or delaying Opportunity creation.
- **FR-004**: System MUST make name resolution self-throttling against the Meta Marketing API's rate limits, and MUST retry with backoff on rate-limit or transient failures rather than failing immediately.
- **FR-019**: System MUST cache resolved campaign/ad-set/ad names per raw campaign source identifier for 12 hours; Opportunities resolving against an unexpired cache entry MUST reuse it without issuing a new external API call, and MUST re-query and refresh the cache once the entry expires.
- **FR-005**: System MUST track, per Opportunity, a resolution status distinguishing: no campaign data present, campaign data present but not yet resolved, successfully resolved, and permanently failed after retries are exhausted.
- **FR-006**: System MUST reflect the current resolution status and available attribution data live on the Opportunity card in the UI as soon as it changes, without requiring a manual page refresh.
- **FR-007**: On permanent resolution failure, system MUST continue showing the raw platform and campaign identifier as a fallback rather than showing no attribution information.
- **FR-008**: System MUST provide a boolean automation condition, available on the message-created automation trigger, that evaluates to true when the triggering message carries campaign referral data and false otherwise.
- **FR-009**: The automation condition in FR-008 MUST be independent of the literal text content of the triggering message (i.e. must not rely on matching suggested/pre-filled message text).
- **FR-010**: System MUST provide a one-time administrative operation that backfills attribution data (per FR-001) onto existing Opportunities created before this feature existed, using their origin conversation's message history to recover campaign referral data.
- **FR-011**: The backfill operation MUST be safely re-runnable: Opportunities already processed in a prior run MUST NOT be reprocessed or have their data overwritten with duplicate work.
- **FR-012**: The backfill operation MUST skip Opportunities belonging to accounts where the feature is not enabled, and MUST report at completion how many Opportunities were processed, skipped for lacking recoverable data, and skipped due to account gating.
- **FR-013**: System MUST provide an account-level master toggle that gates asynchronous name resolution (and the backfill operation); synchronous capture of raw attribution data (FR-001) MUST work regardless of this toggle's state.
- **FR-014**: System MUST require a distinct authenticated connection scoped for campaign-data access before performing name resolution, kept as a fully separate configuration surface — including separate external app credentials — from any existing WhatsApp-channel-connection authentication in the product.
- **FR-020**: The campaign-data connection (FR-014) MUST be established via a two-tier configuration: a Super-Admin-configured, instance-wide external app credential (id/secret/api version), and a per-account authenticated consent performed independently by each Account Administrator against that shared app credential.
- **FR-018**: System MUST restrict configuration of the master toggle and the campaign-data connection (FR-013, FR-014) to Account Administrators.
- **FR-015**: System MUST NOT expose any campaign attribution field other than the boolean "campaign message present" check (FR-008) as an automation filter condition in this release.
- **FR-016**: System MUST NOT store campaign referral data at the conversation level; attribution flows directly from the triggering message to the Opportunity it creates.
- **FR-017**: System MUST apply capture (FR-001) uniformly regardless of which WhatsApp inbox/number the triggering message arrived through, with no per-inbox opt-out in this release.
- **FR-021**: System MUST proactively renew each account's campaign-data connection token before its natural expiry, without requiring the Account Administrator to re-authenticate, as long as the connection remains valid at Meta; re-authentication is only surfaced when proactive renewal is not possible (token already expired or invalidated out-of-band).

### Key Entities

- **Opportunity**: The existing sales/deal record on the Kanban board. Gains new attributes representing campaign attribution: raw campaign source identifier, source URL, originating platform, resolved campaign name, resolved ad-set name, resolved ad name, and a resolution status. These attributes are independent of pipeline/stage configuration — they describe where the Opportunity came from, not what flow it's in.
- **Campaign Referral Data**: The structured signal (source identifier, source URL, platform, headline/body preview, media) already present on an inbound WhatsApp message's content when that message originated from a Click-to-WhatsApp ad click, regardless of which WhatsApp number/inbox delivered it.
- **Automation Rule Condition**: The existing automation-rule-condition concept, extended with one new boolean condition tied to the presence of Campaign Referral Data on a triggering message.
- **Campaign Attribution Connection**: A distinct, account-scoped authenticated connection to the external ad-campaign data source, gating name resolution and backfill, separate from any existing WhatsApp-channel connection. Established per-account by an Account Administrator's own authenticated consent against a shared, instance-wide external app credential.
- **Campaign Data App Credential**: A Super-Admin-configured, instance-wide external app credential (id/secret/api version) that every account's Campaign Attribution Connection authenticates against. Configured once per Chatwoot instance, independent of any existing WhatsApp-channel app credential.
- **Campaign Resolution Cache Entry**: A resolved campaign/ad-set/ad-name (and platform, when derived asynchronously) result keyed by raw campaign source identifier, valid for 12 hours, shared across all Opportunities referencing the same identifier to avoid redundant external API calls.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An agent can identify the ad platform origin of a campaign-sourced Opportunity within 1 second of the card appearing on the board (no loading step required for the platform indicator).
- **SC-002**: For Opportunities eligible for resolution (toggle enabled, authentication configured), at least 95% show resolved campaign/ad-set/ad names within 10 minutes of Opportunity creation under normal operating conditions (no external API outage).
- **SC-003**: 100% of Opportunities created from a message carrying campaign referral data show at minimum a platform indicator, even when name resolution has not yet completed or has permanently failed.
- **SC-004**: An administrator can run the historical backfill once against a live production account without exceeding the external campaign-data API's rate limits and without any manual throttling steps.
- **SC-005**: An automation rule using the new campaign-message condition continues to fire correctly on 100% of test messages where the lead has edited or fully replaced the suggested opening text before sending.
- **SC-006**: Zero Opportunity-creation operations are measurably delayed or blocked by campaign name resolution, since resolution runs asynchronously and does not sit in the creation path.

## Assumptions

- Campaign referral data has already been made available, in a normalized shape, on the first inbound message's content across both supported WhatsApp integration paths (Cloud API and the self-hosted Evolution API integration) — this was completed and validated as prior work (Part 1) and is a precondition for this feature, not part of its scope.
- The `create_opportunity` automation action remains the single place in the product where an Opportunity is created from a triggering message; this feature attaches its capture logic there rather than introducing a new listener or storage layer.
- Chatwoot is a multi-tenant SaaS: a Super Admin configures one instance-wide Meta app credential, and every Chatwoot account independently connects and manages its own Meta campaign-data connection on top of it (own OAuth-authenticated token, own ad account). The `CampaignAttributionSetting` data model (one row per Chatwoot account) already reflects this. The scope limit for this release is narrower and only per-account: each Chatwoot account connects a single Meta ad account's worth of campaign data — an account managing multiple Meta ad accounts simultaneously is out of scope.
- Manual retry tooling for a permanently failed resolution is not required in this release — the raw fallback identifier (FR-007) is considered sufficient until real-world usage shows otherwise.
- The master toggle and campaign-data connection are expected to live within the existing pipeline/card-setup settings area (the tab that may later be generalized into a "CRM setup" section), since resolved campaign data surfaces on the Opportunity card — a stated preference, not a hard product-scope requirement, so exact screen/tab placement remains an implementation-level decision.
- "Within the current week" is a delivery target for planning purposes, not a functional requirement to be verified by this specification.
