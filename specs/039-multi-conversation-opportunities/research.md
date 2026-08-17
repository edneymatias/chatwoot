# Research: Multi-Conversation Opportunity Lifecycle

## Decision 1: Domain & Data Model for Multi-Conversation Lifecycle

### Context
Previously, `ichatr_opportunities` contained a single `origin_conversation_id` column with an immutability validator (`validate_origin_conversation_id_immutability`). This tightly coupled the opportunity to a single conversation. When that conversation was resolved, the opportunity remained locked to the closed chat.

### Validation Findings
- `origin_conversation_id` is used across referral attribution (`ReferralAttributionService`, Meta Ads resolution) and audit history. Retaining it as immutable preserves lead acquisition provenance.
- In `OpportunityActionService` and `OpportunityConditionsFilterService`, `@conversation = opportunity.origin_conversation` currently breaks on manually created opportunities without an origin chat and targets stale closed chats when a newer conversation is active. Resolving to `opportunity.active_conversation || opportunity.origin_conversation` fixes this bug.
- `Conversation` already has `Conversation.include_mod_with('Concerns::Conversation')` at the bottom of `app/models/conversation.rb`. We can cleanly add associations in `custom/app/models/custom/concerns/conversation.rb` (`has_many :opportunity_conversations`, `has_one :active_opportunity`) without editing core files.

### Decision
1. Add `active_conversation_id` (bigint, nullable, references `conversations(id)`) to `ichatr_opportunities` with a partial unique index (`where: 'active_conversation_id IS NOT NULL'`) to enforce at most one active opportunity per open conversation at the DB level.
2. Introduce a new join table `ichatr_opportunity_conversations` (model `OpportunityConversation` under `custom/app/models/opportunity_conversation.rb`):
   - Columns: `id`, `account_id` (bigint, not null), `opportunity_id` (bigint, not null), `conversation_id` (bigint, not null), `is_origin` (boolean, default: false), `created_at`, `updated_at`.
   - Unique compound index on `[:opportunity_id, :conversation_id]`.
   - Index on `[:account_id, :conversation_id]`.
3. In `Opportunity` (`custom/app/models/opportunity.rb`):
   - `belongs_to :active_conversation, class_name: 'Conversation', optional: true`
   - `belongs_to :origin_conversation, class_name: 'Conversation', optional: true`
   - `has_many :opportunity_conversations, class_name: 'OpportunityConversation', dependent: :destroy`
   - `has_many :conversations, through: :opportunity_conversations`
   - Helper methods: `attach_conversation!(conversation, set_active: true)`, `detach_active_conversation!`.
4. Include a data migration to backfill existing opportunities into `OpportunityConversation` (`is_origin: true`) and populate `active_conversation_id = origin_conversation_id` for currently open conversations.

---

## Decision 2: Conversation Status Change Lifecycle Hooks & ActionCable Sync

### Context
When an agent or automated rule resolves a conversation, the system must release the active conversation slot on any linked opportunity and broadcast the update to all connected Kanban boards.

### Validation Findings
- `Conversation` notifies status changes via `after_update_commit :execute_after_update_commit_callbacks` -> `notify_status_change` -> `dispatcher_dispatch`, firing `conversation_resolved`, `conversation_opened`, `conversation_updated`, and on destroy `conversation_deleted`.
- `ActionCableListener` is registered in `SyncDispatcher#listeners`, meaning methods prepended in `Custom::ActionCableListener` are executed synchronously on the request thread.
- `Opportunity#after_commit :broadcast_opportunity_updated` automatically fires when `active_conversation_id` changes (via `detach_active_conversation!` or `update!`), enqueuing `ActionCableBroadcastJob` for `account_#{account_id}`.
- The frontend ActionCable helper (`app/javascript/dashboard/helper/actionCable.js`) receives `opportunity_updated` and calls `store.dispatch('opportunities/syncOpportunity', data)`, reactively updating cards, lists, and drawers across all active sessions with zero manual reloads.

### Decision
1. Add event hooks in `Custom::ActionCableListener` (`custom/app/listeners/custom/action_cable_listener.rb`):
   - `conversation_resolved(event)`: Finds opportunities where `active_conversation_id == conversation.id` and calls `detach_active_conversation!`.
   - `conversation_opened(event)`: If a reopened conversation was previously linked to an open opportunity that currently has `active_conversation_id: nil`, re-attaches as `active_conversation_id`.
   - `conversation_deleted(event)`: Clears active slot if the deleted conversation was active.

---

## Decision 3: "Start Conversation" Flow & Smart Linking Modal

### Context
When an opportunity card has no active conversation (`active_conversation_id.nil?`), the card displays the "Start Conversation" button. Clicking this button should smartly detect if the contact already has open conversations.

### Validation Findings
- `contactConversations` store module (`store.dispatch('contactConversations/get', contactId)`) fetches conversations via `GET /contacts/:id/conversations` (`ContactAPI.getConversations`).
- Open conversations can be filtered with `conversations.filter(c => c.status === 'open')`.
- In `StartOpportunityConversationButton.vue`, we can intercept the trigger click, fetch the contact's conversations, and branch based on open conversation count.

### Decision
1. In `StartOpportunityConversationButton.vue`:
   - Inspect open conversations for the contact.
   - **If 0 open conversations**: Immediately open `ComposeConversation` popover to draft and send a message. Once created, attach as `active_conversation_id`.
   - **If 1+ open conversations**: Open `OpportunityConversationLinkModal.vue` presenting:
     1. **Link Existing Open Conversation**: List open conversation(s) with channel icon, inbox name, preview text, and warning if active on another deal (with transfer confirm option).
     2. **Start a New Conversation**: Proceed to `ComposeConversation` popover.
2. Store action `opportunities/linkConversation` calling `POST /api/v1/accounts/:account_id/opportunities/:id/link_conversation` or `PATCH /opportunities/:id` with `active_conversation_id`.

---

## Decision 4: Conversation History Timeline in Opportunity Views

### Context
Sales agents and managers need visibility into all conversations (past and present) associated with a deal throughout its lifecycle.

### Validation Findings
- `KanbanCard.vue`, `OpportunityListView.vue`, `Index.vue`, and `ContactOpportunities.vue` currently check `origin_conversation_id`. They need to check `active_conversation_id` for card status/actions, and check `associated_conversations` for history.
- `OpportunityBackfillModal.vue` is the central opportunity modal where custom attributes and stage fields are managed; adding a conversation history timeline integrates seamlessly into its layout.

### Decision
1. Backend `Opportunity#as_json` serializer includes:
   - `active_conversation_id` and `active_conversation_display_id`
   - `origin_conversation_id` and `origin_conversation_display_id` (backward compatibility)
   - `associated_conversations`: Array of objects `[{ id, display_id, status, inbox_name, channel_type, created_at, is_active, is_origin }]` ordered by `created_at desc`.
2. In `OpportunityBackfillModal.vue`:
   - Render a dedicated "Conversation History" section showing each conversation with status badge (Open / Resolved), inbox icon, created date, active tag, and direct link to view messages in the conversation drawer.
