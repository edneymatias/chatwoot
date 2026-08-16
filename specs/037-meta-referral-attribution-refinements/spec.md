# Feature Specification: Meta Referral Attribution Refinements

**Feature Branch**: `037-meta-referral-attribution-refinements`  
**Created**: 2026-08-14  
**Status**: Draft  
**Input**: User description: "docs/kanban/ciclo 8/13-meta-referral-attribution-refinements/spec46.md"

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Organic Post Attribution & Non-Destructive Handling (Priority: P1)

When a prospective customer initiates a WhatsApp conversation from an organic Facebook or Instagram publication or story (rather than a paid ad), the system captures the post's origin, headline, body text, and media preview. The opportunity is marked as an organic post attribution without querying ad-specific marketing endpoints and without triggering false-positive account disconnections.

**Why this priority**: Inbound organic leads currently cause false-positive OAuth failures that disconnect the Meta integration for the entire account, breaking attribution for subsequent paid ad leads.

**Independent Test**: Can be tested by creating an opportunity from an incoming WhatsApp message with organic referral payload (`source_type: "post"`). The opportunity immediately displays organic attribution, preserves headline/text, and leaves the account integration active.

**Acceptance Scenarios**:

1. **Given** an incoming WhatsApp conversation initiated from an organic Instagram or Facebook post, **When** an opportunity is created for this conversation, **Then** the opportunity is identified with organic attribution status, storing the post headline, body snippet, and media preview URL without querying marketing ad endpoints.
2. **Given** an opportunity linked to an organic post, **When** an agent views the opportunity card on the Kanban board, **Then** the card displays the platform icon (Instagram/Facebook) and hovering over it reveals a popover clearly stating "Publicação Orgânica" with the post headline and text snippet.
3. **Given** an organic post attribution is processed, **When** the attribution records are saved, **Then** the account's Meta integration connection remains fully active (`connected: true` and `enabled: true`).

---

### User Story 2 - Accurate OAuth Invalidation & Query Error Isolation (Priority: P1)

When external API requests encounter non-fatal query errors (such as missing nodes, deleted posts, or invalid query parameters), the system isolates the failure to the specific opportunity without disabling the account-wide Meta integration. Only authentic authorization revocation events (expired token, deauthorized app, password change) trigger an account disconnection state.

**Why this priority**: Broad error matching currently treats every API query exception as a revoked token, causing unnecessary downtime and manual reconnection overhead for administrators.

**Independent Test**: Can be tested by executing attribution resolution for an invalid or deleted ad ID. The individual opportunity transitions to failed attribution, but the account-level integration remains enabled and continues resolving valid ads.

**Acceptance Scenarios**:

1. **Given** an opportunity referencing an invalid, deleted, or unqueryable ad ID, **When** attribution resolution is executed, **Then** the opportunity's attribution status is marked as failed, diagnostic error details are logged, and the account's Meta connection remains active.
2. **Given** an account whose Meta authorization token has genuinely expired or been revoked by the user, **When** attribution resolution is attempted, **Then** the system marks the opportunity as failed, safely marks the integration as disconnected, and prompts the administrator to reconnect.
3. **Given** attribution resolution encounters temporary API rate limiting, **When** the error is caught, **Then** the resolution job is rescheduled for automatic retry with backoff without marking the opportunity as permanently failed and without disconnecting the account.

---

### User Story 3 - Visual Attribution Popover with Creative Thumbnail Preview (Priority: P2)

When agents manage opportunities on the Kanban board, they can hover over or click the attribution badge to view a rich preview popover. The popover displays the ad or post creative thumbnail alongside complete campaign/adset/ad or post metadata, keeping the card surface clean while giving instant visual context about what creative attracted the lead.

**Why this priority**: Agents need quick visual recognition of the specific promotion, product, or creative that brought the customer in, without adding visual noise or layout shifts to the Kanban board face.

**Independent Test**: Can be tested by opening the Kanban board and hovering over the attribution badge of an opportunity with thumbnail media. The popover renders the creative preview image, title, and attribution hierarchy.

**Acceptance Scenarios**:

1. **Given** an opportunity with resolved ad attribution containing a creative thumbnail, **When** an agent hovers over or clicks the platform badge on the Kanban card, **Then** a popover appears displaying the campaign name, ad set name, ad name, and the creative thumbnail preview.
2. **Given** an opportunity with creative media whose initial remote CDN link may expire, **When** the thumbnail is stored, **Then** the system caches the media file locally/permanently so that the preview continues rendering reliably over time.
3. **Given** an opportunity whose attribution resolution failed, **When** an agent hovers over the attribution indicator, **Then** the popover displays a helpful, human-readable explanation (e.g. "Não foi possível identificar o anúncio ou publicação") rather than a raw numeric ID.

---

### User Story 4 - Automatic Reconnect Drainage & Orphaned Attribution Sweeper (Priority: P2)

When an administrator connects or re-enables the Meta campaign attribution integration after a period of disconnection, or clicks the manual reprocessing button in settings, all backlog opportunities stuck in pending status are automatically queued and resolved. A scheduled background sweeper also checks periodically for any stranded pending attributions.

**Why this priority**: Eliminates manual database interventions and ensures opportunities created during downtime are systematically resolved once connectivity is restored.

**Independent Test**: Can be tested by having pending opportunities while disconnected, reconnecting the integration via Settings, and observing that pending opportunities automatically transition to resolved without manual scripts.

**Acceptance Scenarios**:

1. **Given** multiple opportunities stuck in pending status while Meta integration was disabled, **When** an administrator connects or enables the Meta integration in Settings, **Then** all pending opportunities for that account are automatically queued for background resolution.
2. **Given** an administrator in the Campaign Attribution Settings tab, **When** they view the screen, **Then** they see the current count of pending opportunities and a "Reprocessar Pendentes" button that enqueues drainage and provides immediate feedback.
3. **Given** opportunities in pending status older than 15 minutes in an active account, **When** the scheduled hourly sweeper runs, **Then** the stranded opportunities are detected and queued for resolution.

---

### Edge Cases

- What happens when an incoming referral payload contains neither `source_type: "post"` nor an identifiable ad ID?
  - The opportunity is marked as `campaign_resolution_status: 'not_applicable'` or `failed`, with no external API calls made.
- What happens when a creative thumbnail image download fails or returns HTTP 404/403?
  - The failure is logged and handled gracefully; the opportunity attribution is preserved and falls back to text-only popover display without breaking the resolution workflow.
- What happens when hundreds of pending opportunities are drained at once upon reconnection?
  - The drainage process spaces out job executions or respects rate limit quotas, automatically retrying with backoff if rate limits are approached.
- What happens if the Meta API returns an unrecognized error payload structure?
  - The error is logged under generic API failure, marking the individual opportunity as failed without disabling the account integration.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST identify incoming WhatsApp referrals with `source_type == "post"` or organic post characteristics as organic attributions (`organic_post`) synchronously upon opportunity creation.
- **FR-002**: System MUST extract and persist organic post metadata, including `campaign_headline`, `campaign_body`, and `campaign_thumbnail_url`, on the opportunity record.
- **FR-003**: System MUST NOT dispatch Marketing API ad query requests for opportunities identified as organic posts.
- **FR-004**: System MUST distinguish between fatal authorization errors (token invalid, expired, revoked) and non-fatal query errors (node not found, field error, invalid parameters) from Meta Graph API.
- **FR-005**: System MUST ONLY disconnect the account integration (`enabled = false` and token cleared) upon explicit authentication revocation (`code: 190` with matching subcodes).
- **FR-006**: System MUST mark individual opportunities as failed without disconnecting the account integration when encountering non-fatal query errors (`code: 100`, 404, or unresolvable nodes).
- **FR-007**: System MUST automatically retry attribution resolution with exponential backoff when encountering API rate limits (`code: 17/32/613` or HTTP 429).
- **FR-008**: System MUST persist creative thumbnail media permanently to avoid broken previews when external CDN signatures expire.
- **FR-009**: System MUST render the origin platform icon (Instagram/Facebook) on the Kanban card face for both paid ads and organic posts, keeping the card face compact and text-only.
- **FR-010**: System MUST render a rich popover on hover/click of the attribution badge displaying complete attribution hierarchy, organic post snippet, human-readable failure explanations, and creative thumbnail preview when available.
- **FR-011**: System MUST automatically trigger background resolution for all pending opportunities belonging to an account whenever the Meta integration is connected or enabled.
- **FR-012**: System MUST run a periodic scheduled background sweeper to identify and enqueue resolution for any pending opportunities older than 15 minutes in active accounts.
- **FR-013**: System MUST provide a manual "Reprocess Pending" action button in the Campaign Attribution Settings interface that displays pending counts and triggers immediate background drainage with toast notifications.
- **FR-014**: System MUST support complete synchronous internationalization across English (`en`) and Brazilian Portuguese (`pt-BR`) for all new backend messages, UI labels, tooltips, and popovers.

### Key Entities

- **Opportunity Attribution Data**:
  - `campaign_source_id`: The external ad or post identifier.
  - `campaign_source_url`: The referral source URL.
  - `campaign_platform`: The origin platform (`facebook` / `instagram`).
  - `campaign_name`: Name of the marketing campaign.
  - `campaign_adset_name`: Name of the ad set.
  - `campaign_ad_name`: Name of the specific ad.
  - `campaign_headline`: Headline or title text of the post or ad.
  - `campaign_body`: Main copy or body text of the post or ad.
  - `campaign_thumbnail_url`: Initial CDN or persistent URL for creative media preview.
  - `campaign_resolution_status`: Status enum (`pending`, `resolved`, `organic_post`, `failed`, `not_applicable`).
- **Campaign Attribution Setting**:
  - `enabled`: Boolean indicating whether attribution resolution is actively enabled for the account.
  - `provider_config`: Secure configuration storage containing access tokens and integration metadata.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of organic post referrals are captured and displayed with organic attribution without generating any ad API query errors or false-positive disconnections.
- **SC-002**: 0% false-positive account disconnections occur due to query errors, missing nodes, or malformed ad IDs.
- **SC-003**: 100% of stuck pending opportunities are automatically queued for resolution within 60 seconds of an administrator reconnecting or enabling the Meta integration.
- **SC-004**: Agents can access complete visual creative previews and attribution details on Kanban cards in under 1 second via hover/click popover interaction.
- **SC-005**: All error tooltips provide human-readable diagnostic descriptions with zero raw numeric error codes displayed to end users.
- **SC-006**: No orphaned pending opportunities remain in active accounts longer than 60 minutes.

---

## Assumptions

- Incoming WhatsApp messages continue providing referral metadata via standard webhook payloads (`content_attributes['referral']`).
- Meta Graph API v22.0 remains the active baseline version for marketing endpoints.
- ActiveStorage or existing asset attachment mechanisms are available for caching creative media files locally/cloud storage.
- Kanban cards maintain a uniform text-first surface layout, delegating media previews to the interactive popover overlay.
- All user-facing strings are delivered in both English (`en`) and Portuguese (`pt-BR`) per repository governance standards.
