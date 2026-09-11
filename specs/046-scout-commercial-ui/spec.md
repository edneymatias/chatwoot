# Feature Specification: Scout Commercial Configuration UI

**Feature Branch**: `046-scout-commercial-ui`

**Created**: 2026-08-19

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 9/scout/05-commercial-ui/spec66.md"

## Clarifications

### Session 2026-08-19

- Q: When the Playground triggers a Scout's external REST/webhook tool, should it actually call that real third-party endpoint, or should external tool calls be simulated in test mode? → A: Playground always calls the real external endpoint, no mocking and no confirmation gate — the real tool is always the one that gets called.
- Q: Are there restrictions on the file types and size of documents an admin/agent can upload to a Scout's knowledge base? → A: Follow Captain's existing document-upload rules — PDF only, 10MB max per file.
- Q: Should the number of products, knowledge sources, or external tools an admin/agent can add to a single Scout be capped, or left unlimited? → A: Unlimited — no count cap on products, knowledge sources, or tools per Scout, consistent with Captain not capping FAQs/documents per assistant.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Admin configures a Scout end to end (Priority: P1)

An account admin creates a new Scout, attaches it to an inbox, and fills in the commercial
configuration — product/service catalog, commercial knowledge base, and funnel/qualification
settings — entirely from a dedicated business-configuration area of the dashboard, without needing
to touch the account's Settings area or ask an engineer to configure anything via console.

**Why this priority**: This is the core value of the feature — without it, Scouts can only be
configured by someone with direct database/console access, which blocks any real commercial
rollout.

**Independent Test**: Can be fully tested by logging in as an admin, creating a Scout, associating
it with an inbox, adding at least one product, one knowledge source, and a funnel stage mapping,
and confirming the Scout is saved with all of this configuration intact.

**Acceptance Scenarios**:

1. **Given** an admin is on the dashboard, **When** they open the Scout section from the primary
   menu and create a new Scout, **Then** the Scout is created and the admin can attach it to one or
   more inboxes.
2. **Given** an existing Scout, **When** the admin adds a product/offer entry (name, pricing,
   value proposition), **Then** the entry is saved and listed on the Scout's product catalog tab.
3. **Given** an existing Scout, **When** the admin adds a knowledge source (a URL to crawl, an
   uploaded document, or an FAQ/objection-handling entry), **Then** the source is saved and listed
   on the Scout's knowledge base tab.
4. **Given** an existing Scout, **When** the admin selects the initial triage stage, the qualified
   stage, and the unqualified/discard stage, and chooses which qualification fields the Scout must
   collect, **Then** these funnel settings are saved and reflected when the Scout is reopened.
5. **Given** an existing Scout, **When** the admin adds an external tool (a REST API or webhook
   the Scout can call), **Then** the tool is saved and appears in the Scout's tools list.

---

### User Story 2 - Agent access mirrors admin for business config, but not for LLM credentials (Priority: P2)

A non-admin agent with dashboard access can open and use all the same business-configuration
screens as an admin (Scout list/edit, product catalog, knowledge base, funnel config, tools,
playground), but cannot reach the screen where LLM provider and API key are configured, which
stays admin-only.

**Why this priority**: Commercial configuration (products, FAQs, funnel stages) is business
day-to-day work that sales/ops staff should be able to own, while provider credentials are a
security-sensitive setting that must stay restricted — this split must hold from day one to avoid
either over-restricting business users or exposing API keys.

**Independent Test**: Can be fully tested by logging in as a non-admin agent, confirming the Scout
business-configuration screens are reachable and usable, and confirming the LLM/provider settings
screen is not accessible (blocked or hidden).

**Acceptance Scenarios**:

1. **Given** a logged-in agent (non-admin), **When** they navigate to the Scout primary-menu
   section, **Then** they can view and edit Scout list/detail, product catalog, knowledge base,
   funnel config, and tools screens.
2. **Given** a logged-in agent (non-admin), **When** they attempt to navigate to the Scout
   provider/API key settings screen, **Then** access is denied.
3. **Given** a logged-in admin, **When** they navigate to the Scout provider/API key settings
   screen, **Then** they can view and edit the provider, model, and API key configuration.

---

### User Story 3 - Test a Scout's tool-calling behavior in a playground (Priority: P3)

An admin or agent opens a Playground screen for a Scout and simulates a conversation that
triggers one of the Scout's tools (native or external), seeing the tool call and its result
displayed, without needing to send a real WhatsApp message through a live inbox.

**Why this priority**: Configuring products, knowledge, and tools is only useful if staff can
verify the Scout behaves correctly before turning it loose on real customer conversations; this
closes the configuration loop but is not required to persist the configuration itself.

**Independent Test**: Can be fully tested by opening the Playground for a configured Scout,
sending a test message that should trigger a tool, and confirming the tool call and its result are
displayed on screen.

**Acceptance Scenarios**:

1. **Given** a Scout with at least one enabled tool, **When** a user sends a Playground test
   message that should trigger that tool, **Then** the tool call and its result are shown in the
   Playground without any WhatsApp message being sent or received.
2. **Given** a Scout with no tools enabled, **When** a user sends a Playground test message,
   **Then** the Scout's plain conversational reply is shown.

---

### Edge Cases

- What happens when an admin tries to delete or unassign a pipeline stage that a Scout currently
  uses as its triage/qualified/unqualified stage? The funnel config UI must surface that the stage
  is in use.
- What happens when a knowledge base URL fails to crawl, or an uploaded document fails to process?
  The knowledge base tab must show the source with a failed/error state rather than silently
  dropping it.
- What happens when an agent (non-admin) directly opens the URL of the provider/API key settings
  screen? Access must still be denied server-side, not just hidden from navigation.
- What happens when a Scout has no inbox attached yet? The Scout can still be created and
  configured, but should be visibly marked as not yet live/connected.
- What happens when the Playground triggers an external tool (REST/webhook) that fails or times
  out? The failure must be shown in the Playground result, not treated as a silent success.
- What happens when a Playground test triggers an external tool that has real-world side effects
  (e.g., an ERP webhook that creates an order)? The Playground calls the real endpoint exactly as a
  live conversation would — there is no simulated/dry-run mode, so any side effect happens for
  real.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a primary-menu (not Settings) section where admins and agents
  can list, create, and edit Scouts.
- **FR-002**: System MUST let admins and agents associate a Scout with one or more inboxes, and
  view/remove existing associations.
- **FR-003**: System MUST provide a product/service/offer catalog tab per Scout where users can
  add, edit, and remove entries covering item name, pricing/plan details, and a value-proposition
  summary the Scout can use in sales conversations.
- **FR-004**: System MUST provide a commercial knowledge base tab per Scout supporting three kinds
  of sources: crawled URLs (sales/landing pages), uploaded documents (catalogs, price sheets,
  warranty policies), and FAQ/objection-handling entries; users can add, edit, and remove entries
  of each kind. Uploaded documents MUST be restricted to PDF format with a maximum size of 10MB per
  file, matching Captain's existing document-upload rules; a file that fails this validation MUST
  be rejected with a clear error instead of being accepted and silently failing later.
- **FR-005**: System MUST provide a funnel & qualification configuration tab per Scout where users
  select the initial triage stage, the qualified stage, and the unqualified/discard stage from the
  account's existing pipeline stages, and select which qualification fields the Scout must collect
  from leads.
- **FR-006**: System MUST provide a screen for creating, editing, enabling/disabling, and deleting
  external tools (REST API/webhook definitions) that a Scout can call.
- **FR-007**: System MUST provide a Playground screen per Scout that lets a user send a test
  message and see the Scout's reply, including any tool call triggered and its result, without
  sending or receiving any real conversation message. Tool calls triggered from the Playground —
  native and external (REST/webhook) alike — MUST always execute for real against the tool's live
  endpoint; there is no mocked/simulated tool execution mode.
- **FR-008**: System MUST restrict LLM provider and API key configuration to a separate,
  admin-only screen, distinct from the primary-menu business-configuration screens.
- **FR-009**: System MUST allow both admins and agents to access the primary-menu Scout screens
  (list/edit, product catalog, knowledge base, funnel config, tools, playground).
- **FR-010**: System MUST deny agents (non-admins) access to the LLM provider/API key screen, even
  via direct navigation.
- **FR-011**: System MUST present all user-facing text through the application's translation
  system, in both English and Portuguese, with no untranslated/bare strings.
- **FR-012**: System MUST let an admin set a Scout's response quota as a plain numeric value on the
  Scout's configuration screen (no subscription/billing flow).

### Key Entities *(include if feature involves data)*

- **Scout**: A configured commercial assistant — its identity/persona, provider selection, funnel
  stage mapping, product catalog, knowledge sources, enabled tools, and quota.
- **Scout–Inbox association**: Links a Scout to the inbox(es) it is active on.
- **Product/Offer entry**: An item in a Scout's product catalog — name, pricing/plan details, and
  value-proposition summary.
- **Knowledge source**: A crawled URL, uploaded document, or FAQ/objection-handling entry attached
  to a Scout's commercial knowledge base.
- **Qualification field**: An attribute (e.g., main pain point, estimated budget, decision
  timeline, decision maker) the Scout is configured to collect during qualification.
- **External tool**: A REST API or webhook definition a Scout can call, with its name, description,
  endpoint, and enabled state.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An admin can go from "no Scout exists" to "a fully configured Scout attached to an
  inbox, with at least one product, one knowledge source, and funnel stages set" in a single
  session, without leaving the dashboard.
- **SC-002**: 100% of business-configuration screens (Scout list/edit, product catalog, knowledge
  base, funnel config, tools, playground) are reachable by both admin and agent roles; 0% of
  attempts by an agent to reach the LLM provider/API key screen succeed.
- **SC-003**: A user can validate that a newly configured tool works correctly using the
  Playground, without sending a single real message through a live inbox.
- **SC-004**: 100% of user-facing text in the new screens is translated and available in both
  English and Portuguese at release.

## Assumptions

- The primary-menu Scout section and its admin-only Settings counterpart follow the same
  structural and permission pattern Chatwoot already uses for its Captain feature, rather than
  introducing a new navigation or permission pattern.
- "Agent" in this spec means any authenticated dashboard user with agent-level access, following
  the same permission split already applied to Captain's business-configuration screens.
- Document upload processing and URL crawling for the knowledge base run asynchronously; the UI
  reflects source state (pending/ready/failed) rather than blocking on processing. Document uploads
  follow Captain's existing constraints: PDF only, 10MB max per file.
- The Playground executes a real tool-calling round trip (including external REST/webhook tools)
  against the Scout's live configuration; it does not create or modify any real Chatwoot
  conversation record as a side effect, but calls to external REST/webhook tools reach the real
  third-party endpoint and may have real side effects on that external system — the Playground does
  not mock or gate external tool execution.
- Response quota is a simple numeric field with no plan/subscription selection UI, consistent with
  quota being set directly rather than through a billing flow.
- Pipeline stage options offered in the funnel configuration tab are the account's existing
  `PipelineStage` records; no separate "pipeline" concept is introduced.
- No limit is imposed on the number of products, knowledge sources, or external tools a single
  Scout can have; usage is governed by the existing response quota, not by entry counts.
