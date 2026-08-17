# Quickstart: Multi-Conversation Opportunity Lifecycle Validation

## Overview

This guide describes end-to-end validation scenarios for the Multi-Conversation Opportunity Lifecycle feature.

---

## Scenario 1: Automatic Conversation Detachment on Closure

### Objective
Verify that resolving an open conversation attached to an opportunity automatically clears the opportunity's active conversation slot and restores the "Start Conversation" button on the Kanban card.

### Steps
1. Navigate to the Kanban board (`/app/accounts/{accountId}/opportunities`).
2. Identify or create an opportunity linked to an active conversation (Card has a chat link/bubble).
3. Click the card or conversation icon to open the active conversation in the drawer or inbox.
4. Mark the conversation as **Resolved** (`Resolvida`).
5. Observe the Kanban card in realtime (or without refresh):
   - The card's active conversation state transitions to unlinked/idle.
   - The "Start Conversation" button (`i-lucide-message-square-plus`) appears in the card's action footer.
   - The deal remains in its exact current pipeline stage and retains all custom field values.

---

## Scenario 2: Smart Conversation Linking Modal (Existing Open Chat)

### Objective
Verify that clicking "Start Conversation" on an opportunity whose contact has an existing open conversation opens a modal asking to link or start a new chat.

### Steps
1. Ensure the contact for Opportunity A has an open conversation (e.g. Conversation #101) in Chatwoot.
2. In the Kanban board, find Opportunity A (which currently has no active conversation).
3. Click the "Start Conversation" button on the card.
4. **Expected Result**: A prompt/dialog appears stating:
   - "This contact already has open conversation(s)."
   - Option 1: "Link existing open conversation (#101)"
   - Option 2: "Start a new conversation"
5. Select "Link existing open conversation".
6. **Expected Result**:
   - Opportunity A sets Conversation #101 as its active conversation.
   - The Kanban card updates immediately to link to Conversation #101.

---

## Scenario 3: Start New Conversation from Opportunity Card

### Objective
Verify that clicking "Start Conversation" for a contact with no open conversations directly opens the new conversation composer and attaches the new chat as active.

### Steps
1. Find an opportunity whose contact has no open conversations in Chatwoot.
2. Click the "Start Conversation" button on the card.
3. **Expected Result**: Directly opens the `ComposeConversation` popover.
4. Select an inbox, type a message, and send.
5. **Expected Result**:
   - The newly created conversation is set as `active_conversation_id` on the opportunity.
   - The conversation is added to `ichatr_opportunity_conversations`.
   - The Kanban card updates to link to the new conversation.

---

## Scenario 4: Conversation History in Opportunity Details

### Objective
Verify that the opportunity drawer/modal displays the complete timeline of all conversations associated with the opportunity.

### Steps
1. Open the Opportunity Details drawer/modal for an opportunity with multiple past and active conversations.
2. Navigate to the "Conversation History" / "Histórico de Conversas" section.
3. **Expected Result**:
   - The currently active conversation is displayed with an "Active" / "Em andamento" badge.
   - Past resolved conversations are listed with "Resolved" / "Resolvida" badges and resolution timestamps.
   - Clicking on any conversation item navigates directly to that conversation thread.

---

## Automated Test Execution Commands

### Backend Specs (RSpec)

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/models/opportunity_spec.rb custom/spec/models/opportunity_conversation_spec.rb custom/spec/listeners/custom/action_cable_listener_spec.rb custom/spec/controllers/api/v1/accounts/opportunities_controller_spec.rb
```

### Frontend Tests (Vitest)

```bash
docker compose exec vite pnpm test
```

### Code Style & Lints

```bash
docker compose exec rails bundle exec rubocop
docker compose exec vite pnpm eslint
```
