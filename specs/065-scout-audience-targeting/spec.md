# Feature Specification: Scout Audience Targeting

**Feature Branch**: `065-scout-audience-targeting`

**Created**: 2026-09-10

**Status**: Draft

**Input**: User description: "@docs/kanban/ciclo 10/scout/25-scout-audience-targeting/spec88.md" — Fase 25 do Scout: adicionar um público-alvo opcional por Scout (lista de condições sobre contato/conversa) que decide se um contato é atendido pelo Scout ou encaminhado direto para a fila humana, permitindo rollout controlado em produção.

## Clarifications

### Session 2026-09-10

- Q: When an admin edits a Scout's target audience so that a contact no longer matches, should conversations already pending with that Scout for that contact be moved to the human queue right away, or only affect conversations created/reopened after the change? → A: Forward-only — audience changes apply only to conversations created or reopened after the change; already-pending Scout conversations are left untouched.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Define a target audience for a Scout (Priority: P1)

An admin configuring a Scout for an inbox wants to limit which contacts the Scout automatically engages, so they can roll it out to a small, controlled group of contacts (e.g. a specific phone number list, or contacts with a certain label) before opening it up to everyone writing to that inbox.

**Why this priority**: This is the core capability of the feature — without it, there is no way to control who the Scout engages, and the rest of the feature (routing non-matching contacts elsewhere) has nothing to act on. It directly unblocks safe production rollout, which is the stated business problem.

**Independent Test**: Can be fully tested by configuring one or more targeting conditions on a Scout (e.g. "phone number equals X") and confirming that a conversation started by a contact matching that condition is engaged by the Scout.

**Acceptance Scenarios**:

1. **Given** a Scout with no target audience configured, **When** an admin opens the Scout's configuration, **Then** they see an empty audience state explaining the Scout currently engages every contact in the inbox.
2. **Given** a Scout's configuration screen, **When** an admin adds one or more targeting conditions (e.g. contact attribute, label, or custom attribute matching specific values) and saves, **Then** the conditions are persisted against that Scout.
3. **Given** a Scout with saved targeting conditions combining multiple rules (e.g. "label is X" AND "country is Y", or "phone is A" OR "phone is B"), **When** the conditions are evaluated for a contact, **Then** the combination logic (AND/OR) is applied in the order the conditions were configured.
4. **Given** a Scout's targeting configuration, **When** an admin removes all conditions and saves, **Then** the Scout reverts to engaging every contact in the inbox.

---

### User Story 2 - Route non-matching new conversations to the human queue (Priority: P2)

A contact who does not match a Scout's configured target audience writes to the inbox for the first time. Instead of being silently ignored or left in limbo, their conversation must go straight to the normal human support queue, just as it would if the Scout were disabled entirely.

**Why this priority**: Without this, turning on audience targeting would create abandoned conversations for every contact outside the audience — a worse outcome than not having the feature at all. This is what makes P1 safe to use in production.

**Independent Test**: Can be fully tested by configuring a target audience that excludes a specific contact, having that contact start a new conversation, and confirming the conversation appears in the normal (human-attended) queue rather than waiting on the Scout.

**Acceptance Scenarios**:

1. **Given** a Scout with a configured target audience, **When** a contact who matches the audience starts a new conversation, **Then** the conversation is handled by the Scout as normal.
2. **Given** a Scout with a configured target audience, **When** a contact who does NOT match the audience starts a new conversation, **Then** the conversation is immediately available in the normal human queue instead of waiting on the Scout.

---

### User Story 3 - Route reopened non-matching conversations to the human queue (Priority: P3)

A contact who does not match a Scout's target audience sends a new message on a conversation that had already been resolved. That reopened conversation must also go to the human queue, not back to the Scout.

**Why this priority**: This closes a secondary but real gap — without it, an excluded contact could still end up back in the Scout's hands simply by messaging into an old, resolved conversation. Lower priority than new conversations (P2) because it's a narrower, less frequent path, but still needed for the feature's safety guarantee to hold consistently.

**Independent Test**: Can be fully tested by resolving a conversation for a contact outside the audience, having that contact send a new message, and confirming the conversation reopens into the human queue rather than being picked back up by the Scout.

**Acceptance Scenarios**:

1. **Given** a resolved conversation with a contact who matches the Scout's audience, **When** the contact sends a new message, **Then** the conversation reopens and is handled by the Scout as before.
2. **Given** a resolved conversation with a contact who does NOT match the Scout's audience, **When** the contact sends a new message, **Then** the conversation reopens directly into the human queue instead of the Scout.

---

### Edge Cases

- What happens when a Scout has no target audience configured at all? The Scout must continue engaging every contact in the inbox, exactly as it does today (no regression for existing Scouts).
- What happens when a single condition cannot be evaluated because its value can't be meaningfully compared (e.g. a numeric/date comparison against a value that isn't a number or date)? That condition evaluates as not matching, and the rest of the audience evaluation continues normally — this is a data problem local to one condition, not a system failure.
- What happens if the targeting evaluation hits a genuine, unexpected system error (a bug, not a bad value)? It is NOT silently treated as a match — see FR-007. Swallowing every possible error into "engage anyway" would let a real defect quietly and permanently disable a Scout's targeting with no signal to anyone, which is worse than letting it surface.
- How does the system handle a targeting condition referencing an attribute the contact has never set (e.g. no label applied, no custom attribute value)? The condition should evaluate as not matching for that attribute rather than raising an error.
- What happens when a targeting condition references data tied to a deal/opportunity rather than the contact? Not supported in this feature — targeting only evaluates contact attributes (see Assumptions). Conversation-level attributes (e.g. browser language) are also out of scope for this phase, since the configuration screen this feature reuses only exposes contact attributes today.
- What happens to a conversation already pending with the Scout when an admin edits the target audience so that contact no longer matches? The conversation is left untouched with the Scout; the updated audience only applies to conversations created or reopened after the change (see Clarifications).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow an admin to define zero or more targeting conditions per Scout, each based on a contact attribute (e.g. name, email, phone number, identifier, blocked status, country, city, company, label, custom attribute). Conversation-level attributes (e.g. browser language) are deferred to a future extension, since configuring them isn't possible until the reused condition-building UI is extended to expose conversation attributes.
- **FR-002**: System MUST allow targeting conditions to be combined using AND/OR logic, evaluated in the sequence the admin configured them.
- **FR-003**: When a Scout has no targeting conditions configured, System MUST engage every contact writing to that Scout's inbox, matching current behavior exactly.
- **FR-004**: When a Scout has targeting conditions configured, System MUST only allow the Scout to engage contacts whose attributes match those conditions.
- **FR-005**: For a new conversation from a contact who does not match a Scout's configured targeting conditions, System MUST route that conversation to the normal human queue instead of leaving it waiting on the Scout.
- **FR-006**: For a resolved conversation reopened by a new message from a contact who does not match a Scout's configured targeting conditions, System MUST route that conversation to the normal human queue instead of returning it to the Scout.
- **FR-007**: If a single targeting condition cannot be meaningfully evaluated because its stored value doesn't fit the comparison being made (e.g. a numeric/date operator against a non-numeric/non-date value), System MUST treat that condition as not matching and continue evaluating the rest of the audience normally, rather than crashing the whole evaluation over one bad value. This is a narrow, per-value safeguard — it MUST NOT be implemented as a blanket "any error means engage the contact" fallback, since that would let a genuine defect silently and permanently disable a Scout's targeting with no operator-visible signal.
- **FR-008**: Admin users MUST be able to create, edit, and remove a Scout's targeting conditions through the Scout's configuration screens.
- **FR-009**: The targeting condition configuration experience MUST offer the same attributes and condition-building interaction already available in the product's existing Contacts/Kanban filtering, so admins do not need to learn a new pattern.
- **FR-010**: System MUST persist each Scout's targeting configuration independently, so different Scouts (across inboxes) can have different target audiences.
- **FR-011**: When an admin changes a Scout's target audience, System MUST apply the updated configuration only to conversations created or reopened after the change; conversations already pending with the Scout at the time of the change MUST NOT be automatically moved as a result of the change alone.

### Key Entities

- **Scout**: The existing AI assistant configured per inbox that automatically engages contacts; gains an optional target audience configuration that scopes which contacts it engages.
- **Targeting Condition**: A single rule within a Scout's target audience — an attribute, a match operator, one or more values, and how it combines (AND/OR) with the condition before it.
- **Contact**: The existing entity whose attributes (name, email, phone, labels, custom attributes, etc.) are evaluated against targeting conditions.
- **Conversation**: The existing entity representing a contact's ongoing or resolved exchange with the inbox; its routing (Scout vs. human queue) is decided using targeting results at creation and at reopening.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An admin can configure a target audience for a Scout and confirm, within the same session, that only matching contacts are engaged by it.
- **SC-002**: 100% of conversations — new or reopened — from contacts outside a Scout's configured target audience land in the normal human queue, with none left unattended waiting on the Scout.
- **SC-003**: Scouts that have no target audience configured show zero change in engagement behavior compared to before this feature existed.
- **SC-004**: Admins can build a target audience using only the same condition-building experience they already know from Contacts/Kanban filtering, without needing engineering assistance.

## Assumptions

- Targeting is scoped to Contact attributes only for this phase. Opportunity/deal attributes are out of scope because a deal may not yet exist at the point targeting is evaluated (conversation creation/reopening, before the Scout has had a chance to create one). Conversation-level attributes are also out of scope for this phase — not for a structural reason like Opportunity, but because the reused condition-building UI currently only exposes contact attributes; adding conversation attributes there is a small, separate, future frontend extension.
- The set of available targeting attributes matches what the product's existing Contacts filter experience already exposes; no new contact attributes are introduced by this feature.
- Targeting conditions are a flat, sequential list (not nested groups); this covers the real-world cases driving this feature (e.g. a list of phone numbers and/or a label) without the added complexity of a nested condition builder.
- Each Scout's target audience is independent — there is no cross-inbox or cross-account sharing of targeting configuration.
- No percentage-based or random-sampling rollout mode is included; targeting is always deterministic based on matching attribute conditions, not statistical sampling.
