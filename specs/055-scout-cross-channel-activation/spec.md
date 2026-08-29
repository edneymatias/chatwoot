# Feature Specification: Scout Cross-Channel Activation

**Feature Branch**: `[055-scout-cross-channel-activation]`

**Created**: 2026-08-28

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 10/scout/16-cross-channel-activation/spec76.md — Fase 16, Ativação do Scout em Qualquer Canal. Corrige dois bugs de causa raiz que impedem o Scout de engajar conversas fora de inboxes WhatsApp: (1) `Custom::ScoutListener` só processa mensagens de inbox `Channel::Whatsapp`; (2) uma conversa nova nunca nasce `pending` em nenhuma inbox com Scout habilitado porque `Inbox#active_bot?` não conhece o Scout, então a pipeline do Scout (que exige `conversation.status == 'pending'`) nunca dispara em nenhum canal."

## Clarifications

### Session 2026-08-28

- Q: When this fix ships, should already-existing conversations that are stuck `open` on an inbox with an already-enabled Scout be retroactively moved to `pending`, or does the fix apply only to conversations created from this point forward? → A: Forward-only — only conversations created after the fix ships are affected; existing stuck `open` conversations are left as-is.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Scout engages new conversations on non-WhatsApp channels (Priority: P1)

An account admin connects a Scout to a Website Widget (or Email, or any other) inbox, exactly as they would for a WhatsApp inbox today. A visitor starts a new conversation on that channel. Today nothing happens — the conversation opens in the normal `open` queue and the Scout never sees it. With this fix, the conversation is recognized as bot-eligible the moment it's created, and the Scout engages it the same way it already does on WhatsApp.

**Why this priority**: This is the core defect. Without it, the Scout feature is silently WhatsApp-only despite that never being a stated product restriction — every other channel is a dead end for automated engagement, which is the exact bug this spec exists to fix.

**Independent Test**: Connect a Scout to a Website Widget inbox, start a new conversation from the widget, and observe the Scout respond to the first message — fully verifiable without touching campaign-attribution or handoff behavior.

**Acceptance Scenarios**:

1. **Given** a Website Widget inbox with an enabled Scout linked to it, **When** a visitor starts a new conversation, **Then** the conversation is created with status `pending`.
2. **Given** that new `pending` conversation, **When** the visitor sends an incoming public message, **Then** the Scout's message-processing pipeline is triggered and the Scout responds, just as it does today on WhatsApp.
3. **Given** an Email inbox with an enabled Scout linked to it, **When** a new conversation arrives, **Then** the same behavior in scenarios 1–2 holds (the fix is channel-agnostic, not Website-Widget-specific).

---

### User Story 2 - Non-Scout inboxes are unaffected (Priority: P2)

An account has ordinary inboxes with no Scout connected, or with a Scout that's been disabled. Conversations on those inboxes must keep behaving exactly as they do today — the fix must not accidentally make every inbox in the system bot-eligible.

**Why this priority**: The mechanism being changed (`Inbox#active_bot?`) is a shared decision point that also governs the legacy Dialogflow/`agent_bot_inbox` bot and, going forward, the Scout bot. A regression here would silently change conversation routing for accounts that have never touched the Scout feature — a correctness risk at least as important as the main fix, though it's the "don't break it" counterpart rather than the feature itself.

**Independent Test**: Create a conversation on an inbox with no Scout linked, and separately on an inbox with a disabled Scout linked; confirm both still start as `open` (or whatever the legacy mechanism already produces), with no Scout job enqueued.

**Acceptance Scenarios**:

1. **Given** an inbox with no Scout linked, **When** a new conversation is created, **Then** it starts as `open` (unchanged from current behavior).
2. **Given** an inbox with a Scout linked but disabled, **When** a new conversation is created, **Then** it starts as `open` (unchanged from current behavior).
3. **Given** an inbox where the legacy `agent_bot_inbox`/Dialogflow bot is active, **When** a new conversation is created, **Then** it still starts as `pending` exactly as it does today, regardless of whether a Scout is also linked.

---

### User Story 3 - Human handoff keeps working across all channels (Priority: P3)

Once a Scout is engaging conversations on channels beyond WhatsApp, the existing "hand off to a human when an agent manually replies" behavior (built in an earlier phase) must keep working unchanged, since it now applies to a wider set of conversations than before.

**Why this priority**: This is a regression check on already-shipped behavior rather than new functionality — the handoff logic itself needs no code change, but its effective scope grows the moment Story 1 ships, so it's worth confirming explicitly rather than assuming.

**Independent Test**: On a non-WhatsApp Scout conversation left `pending`, have an agent send a manual (non-Scout) reply and confirm the conversation is handed off (leaves the Scout's automated flow) the same way it would on WhatsApp.

**Acceptance Scenarios**:

1. **Given** a `pending` conversation on a non-WhatsApp inbox with an enabled Scout, **When** a human agent sends a manual reply, **Then** the conversation is handed off exactly as it would be on a WhatsApp conversation in the same state.

---

### Edge Cases

- A WhatsApp inbox with an enabled Scout must keep working exactly as it does today — this fix must not regress the one channel that already worked.
- An inbox with a Scout that gets disabled *after* a conversation already went `pending` must not change how already-open conversations behave (the fix only changes conversation *creation* status and the incoming-message gate, not existing conversation state retroactively).
- A channel that also carries WhatsApp-only campaign/referral attribution data (CTWA/Meta Referral) must keep behaving exactly as it does today — that logic is already self-gating (it simply finds no referral data on other channels) and is explicitly out of scope for this fix.
- A private (internal) note or an outgoing message on a non-WhatsApp Scout inbox must NOT trigger the Scout pipeline, matching current WhatsApp behavior.
- A conversation that was already stuck `open` on a Scout-enabled inbox *before* this fix ships is NOT retroactively moved to `pending` — the fix is forward-only and only affects conversations created after it ships.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST allow a Scout to engage incoming public messages on a conversation regardless of the inbox's channel type, not just `Channel::Whatsapp`.
- **FR-002**: The system MUST mark a newly created conversation as `pending` whenever it belongs to an inbox that has an enabled Scout linked to it, regardless of channel type.
- **FR-003**: The system MUST leave conversation-creation status unchanged (`open`, unless another existing mechanism such as the legacy Dialogflow bot applies) for inboxes with no Scout linked, or with a Scout linked but disabled.
- **FR-004**: The system MUST preserve all existing legacy bot-activation behavior (`agent_bot_inbox`/Dialogflow) unchanged — the Scout eligibility check is additive, never a replacement.
- **FR-005**: The system MUST continue restricting campaign/referral attribution behavior (CTWA/Meta Referral) to the channels where that data can physically exist; this fix MUST NOT add or remove any gating around that logic.
- **FR-006**: The system MUST continue triggering human handoff on manual agent intervention for any Scout-pending conversation, independent of the inbox's channel type.
- **FR-007**: The system MUST NOT trigger the Scout pipeline for private/internal notes or outgoing messages, on any channel, matching current behavior.
- **FR-008**: The system MUST NOT retroactively change the status of conversations that already exist when the fix ships; only conversations created after the fix is deployed are eligible to start `pending` under the new behavior.

### Key Entities

- **Inbox**: A conversation channel (WhatsApp, Website Widget, Email, etc.) that may or may not have a Scout linked and enabled. Its bot-eligibility state determines whether new conversations start `pending`.
- **Scout**: An automated agent that can be linked to one or more inboxes and toggled enabled/disabled per link. Only an enabled link makes its inbox bot-eligible.
- **Conversation**: Created within an inbox; its initial status (`open` vs. `pending`) determines whether the Scout pipeline is eligible to engage it at all.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A Scout connected to any channel type (not just WhatsApp) engages a new conversation's first message, verified end-to-end via manual test on a Website Widget inbox.
- **SC-002**: 100% of existing WhatsApp Scout behavior (engagement, handoff, campaign attribution) continues to pass its existing test coverage with no regression.
- **SC-003**: 100% of non-Scout and disabled-Scout inboxes show zero change in conversation-creation status or bot behavior compared to before this fix.
- **SC-004**: Human handoff on manual agent intervention continues to function on 100% of Scout-pending conversations regardless of channel.

## Assumptions

- The legacy `agent_bot_inbox`/Dialogflow mechanism remains untouched and is not being migrated, deprecated, or unified with the Scout mechanism as part of this fix — `super ||` composition is sufficient to preserve it.
- Campaign/referral attribution logic (CTWA/Meta Referral, WhatsApp-specific) requires no code changes because it is already self-gating by only finding data where it physically exists.
- "Any channel" means any inbox channel type Chatwoot supports as a Scout-connectable inbox today; no new channel types are introduced by this fix.
- The fix is a bug correction to restore intended scope, not a new feature requiring its own opt-in/feature flag — once shipped, every enabled Scout link becomes immediately active on its inbox's channel.
- The fix is forward-only: no data migration or backfill runs against conversations that already exist at deploy time. An admin who wants an already-stuck conversation picked up by the Scout can resolve it manually (e.g., reply and let normal conversation flow continue).
