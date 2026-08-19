# Research: Scout Native Tools & Message Pipeline

**Branch**: `043-scout-native-tools-pipeline` | **Date**: 2026-08-19 | **Spec**: [spec.md](file:///home/matias/dev/chatwoot/specs/043-scout-native-tools-pipeline/spec.md)

## Context & Objectives

This research document consolidates validated technical decisions for Phase 2 of the Scout AI agent engine, verified against Phase 1 (`specs/042-scout-core-data-model/`), the fork's existing features, upstream Chatwoot (`app/` and `enterprise/`), and `ruby_llm` (1.15.0):
1. Debounce and sliding window buffering in Redis + Sidekiq for incoming WhatsApp messages.
2. Scout runner execution loop, context building, multimodal attachments, and Out-of-Office integration.
3. Fail-Safe handoff architecture (pre-call quota & API key checks + runtime LLM error wrapper).
4. Native Ruby tools implementation (`manage_opportunity`, `move_opportunity_stage`, `update_contact`, `create_private_note`, `handover_to_human`).
5. Preservation of Meta/CTWA campaign referral attribution via existing services (`Custom::ReferralAttributionService`).
6. Contact memory generation on handoff (`Custom::Scout::ContactNotesService` using `scout.llm_chat`).
7. Data model extensions for `Scout` (`ichatr_scouts`).

---

## Technical Decisions

### 1. Debounce Mechanism & Sliding Window via Redis + Sidekiq

- **Decision**: Implement `Custom::Scout::ProcessMessageJob` utilizing Redis timestamps and an atomic debounce lock pattern.
- **Rationale**:
  - WhatsApp leads frequently send 2–4 short messages in rapid succession (a burst).
  - Clarification from spec.md established a **sliding window**: each new incoming message resets the countdown so processing executes $N$ seconds after the *last* message in the burst.
  - Using Redis keys `scout:debounce:conversation:<id>:last_message_at` (stores float timestamp of latest message) and `scout:debounce:conversation:<id>:enqueued` (atomic NX flag) guarantees:
    1. Only one Sidekiq job is scheduled per burst (no duplicate jobs running concurrently).
    2. When the job wakes up, it checks if `Time.current.to_f - last_message_at >= debounce_delay`. If new messages arrived during the delay, the job reschedules itself for the remaining time (`debounce_delay - (Time.current.to_f - last_message_at)`).
    3. When the window has elapsed with no new messages, the lock keys are deleted and `Custom::Scout::AgentRunner.new(scout: scout, conversation: conversation).perform` runs.
- **Alternatives Considered**:
  - *Fixed window (Debounce from first message)*: Rejected during clarification session because mid-burst replies cut off the lead while typing.
  - *Redis Streams or Sidekiq Batches*: Unnecessary operational complexity; a lightweight timestamp comparison in Redis achieves precise sliding debounce with zero added infrastructure.

### 2. Event Listener & Dispatcher Integration (`Custom::ScoutListener`)

- **Decision**: Add `Custom::ScoutListener` to `custom/app/listeners/custom/scout_listener.rb` and register it in `Custom::AsyncDispatcher#listeners`.
- **Rationale**:
  - Core `AsyncDispatcher` (`app/dispatchers/async_dispatcher.rb:27`) has `AsyncDispatcher.prepend_mod_with('AsyncDispatcher')`.
  - `custom/app/dispatchers/custom/async_dispatcher.rb` prepends custom listeners cleanly without modifying core files:
    ```ruby
    module Custom::AsyncDispatcher
      def listeners
        super + [
          Custom::OpportunityActivityListener.instance,
          Custom::ScoutListener.instance
        ]
      end
    end
    ```
  - `ScoutListener#message_created(event)` checks:
    1. `message.incoming? && !message.private?`
    2. `message.inbox.channel_type == 'Channel::Whatsapp'`
    3. `scout = message.inbox.scout` and `scout&.enabled?`
    4. `message.conversation.pending?` (prevents triggering on closed/resolved conversations)
  - When all checks pass, it enqueues the debounced job via `Custom::Scout::ProcessMessageJob.enqueue_debounced(message.conversation, scout)`.

### 3. Fail-Safe Handoff Architecture & Error Boundaries

- **Decision**: Wrap the entire runner execution in two distinct fail-safe gates:
  1. **Pre-call Gate**: Verify `scout.quota_available?` and API key presence (`scout.api_key_override` or `ENV["#{scout.provider.upcase}_API_KEY"]`). If missing/exhausted, immediately execute Fail-Safe handoff and exit before calling RubyLLM.
  2. **Runtime Error Wrapper**: Wrap the entire response generation (context building, LLM provider call, tool calls) in `rescue StandardError => e`. On any unhandled exception (provider 5xx, network timeout, rate limit, JSON parsing error), capture the exception via `ChatwootExceptionTracker`, log the error, and execute Fail-Safe handoff.
- **Fail-Safe Handoff Execution Details**:
  - Guard: Ensure `conversation.pending?` is true.
  - Trigger: Call `conversation.bot_handoff!`.
  - Alert Note: Post a private note using `Messages::MessageBuilder.new(nil, conversation, { content: alert_text, private: true }).perform`:
    `⚠️ [IA Pausada]: A conversa foi transferida para atendimento humano devido a esgotamento de saldo/limite de API.` (or descriptive error message).
  - Memory Note: If `scout.feature_memory?` is true, trigger `Custom::Scout::ContactNotesService.new(scout, conversation).generate_and_update_notes`.
- **Rationale**: Matches the contract specified in spec60.md §4.2 and spec.md User Story 3 / FR-003 / FR-003a, guaranteeing no lead is ever left stranded in `pending`.

### 4. Native Tools Implementation & RubyLLM Tool Architecture

- **Decision**: Define a base tool `Custom::Scout::Tools::BaseTool < RubyLLM::Tool` and 5 native Ruby tools under `custom/app/services/custom/scout/tools/`:
  1. `ManageOpportunity`:
     - Explicit name: `def name; 'manage_opportunity'; end`
     - Parameters:
       - `param :action, type: :string, desc: "Action: 'create' or 'update'", required: false`
       - `param :title, type: :string, desc: 'Opportunity title', required: false`
       - `param :stage_id, type: :integer, desc: 'Target pipeline stage ID', required: false`
       - `param :estimated_value, type: :number, desc: 'Estimated deal value', required: false`
       - `param :custom_attributes, type: :hash, desc: 'Key-value qualification data', required: false`
     - Finds or creates `Opportunity` scoped to `origin_conversation_id: conversation.id`.
     - When creating: Reuses `Custom::ReferralAttributionService.process(opportunity, referral_message)` using the first incoming message with referral data.
     - When updating: Updates fields and merges `custom_attributes` without overwriting referral attribution.
  2. `MoveOpportunityStage`:
     - Explicit name: `def name; 'move_opportunity_stage'; end`
     - Parameters:
       - `param :stage_id, type: :integer, desc: 'Target pipeline stage ID', required: true`
       - `param :lost_reason, type: :string, desc: 'Reason if lost/disqualified', required: false`
     - If no `Opportunity` exists for the conversation, returns `"No opportunity found for this conversation."` gracefully without crashing.
     - Updates `opportunity.pipeline_stage_id = stage_id`. If `lost_reason` is supplied, sets `opportunity.lost_reason = lost_reason` and sets `status = :lost` if the target stage represents lost.
  3. `UpdateContact`:
     - Explicit name: `def name; 'update_contact'; end`
     - Parameters:
       - `param :name, type: :string, desc: 'Contact full name', required: false`
       - `param :email, type: :string, desc: 'Contact email address', required: false`
       - `param :phone, type: :string, desc: 'Contact phone number', required: false`
       - `param :custom_attributes, type: :hash, desc: 'Key-value map of custom attributes', required: false`
     - Updates the conversation's contact attributes and merges custom attributes.
  4. `CreatePrivateNote`:
     - Explicit name: `def name; 'create_private_note'; end`
     - Parameters:
       - `param :content, type: :string, desc: 'Markdown content of the internal note', required: true`
     - Creates a private activity message on the conversation via `Messages::MessageBuilder`.
  5. `HandoverToHuman`:
     - Explicit name: `def name; 'handover_to_human'; end`
     - Parameters:
       - `param :assignee_id, type: :integer, desc: 'Target agent ID', required: false`
       - `param :team_id, type: :integer, desc: 'Target team ID', required: false`
       - `param :reason, type: :string, desc: 'Reason for handoff', required: false`
     - Resolves `team_id` (falls back to `scout.handover_team_id`).
     - Assigns `conversation.assignee_id` / `conversation.team_id`.
     - Calls `conversation.bot_handoff!` if `conversation.pending?`.
     - Creates a private note with the handoff reason if provided.
     - If `scout.feature_memory?`, triggers `Custom::Scout::ContactNotesService.new(scout, conversation).generate_and_update_notes`.
     - Signals the runner to suppress further bot text replies.
- **Rationale**: `RubyLLM::Tool` parameters map directly to JSON schemas; instances registered via `chat.with_tool(tool_instance)` keep execution encapsulated and multi-turn capable.

### 5. Multimodal Attachments & Out-of-Office Handling

- **Decision**:
  - **Attachments**: Extract image and audio attachments from incoming messages in the current burst/turn (`attachment.file_type.in?(%i[image audio])`). Pass `with: attachments.map(&:download_url)` to `chat.ask(prompt, with: attachments)` for the active turn, and use `RubyLLM::Content.new(text, attachments)` for prior history.
  - **Out of Office**: Query `conversation.inbox.out_of_office?` (available via `OutOfOffisable` concern on `Inbox`). If `true`, inject an out-of-office instruction into the prompt context:
    `[System Notice: The team is currently OUT OF OFFICE. Inform the lead if relevant, but proceed with qualification.]`
  - This informs the LLM without blocking or delaying the AI response.

### 6. Contact Memory Service (`Custom::Scout::ContactNotesService`)

- **Decision**: Implement `Custom::Scout::ContactNotesService` directly under `custom/app/services/custom/scout/contact_notes_service.rb` utilizing `scout.llm_chat`.
- **Rationale**:
  - `Captain::Llm::ContactNotesService` in `enterprise/` inherits from `Llm::BaseAiService` which relies on global OpenAI Captain keys, ignoring Scout's multi-provider config (`provider`, `model_name`, BYOK `api_key_override`).
  - Implementing `Custom::Scout::ContactNotesService` ensures:
    1. Full multi-provider compatibility (Gemini, OpenAI, Anthropic) using the Scout's own model and credentials.
    2. Zero dependency on `enterprise/` classes, adhering to Constitution Principle I (`custom/` self-containment).
    3. Reuses `conversation.contact.to_llm_text` and `conversation.to_llm_text` for uniform markdown formatting.
    4. Triggers **only at handoff** (via `HandoverToHuman` or Fail-Safe) when `scout.feature_memory?` is true.

### 7. Data Model Schema Extensions for `Scout`

- **Decision**: Add migration `db/migrate/21260819000005_add_pipeline_fields_to_ichatr_scouts.rb` (sequenced after `21260819000004_add_lost_reason_to_ichatr_opportunities.rb`) to add:
  - `debounce_delay_seconds` (integer, default: 5, null: false)
  - `feature_memory` (boolean, default: true, null: false)
  - `qualified_stage_id` (bigint, FK → `ichatr_pipeline_stages`, null: true, indexed)
  - `unqualified_stage_id` (bigint, FK → `ichatr_pipeline_stages`, null: true, indexed)
  - `handover_team_id` (bigint, FK → `teams`, null: true, indexed)
  - `product_catalog` (jsonb, default: {}, null: false)
  - `knowledge_sources` (jsonb, default: {}, null: false)
- **Associations & Concerns**:
  - `Scout` model:
    - `belongs_to :qualified_stage, class_name: 'PipelineStage', optional: true`
    - `belongs_to :unqualified_stage, class_name: 'PipelineStage', optional: true`
    - `belongs_to :handover_team, class_name: 'Team', optional: true`
    - `alias_attribute :system_prompt, :persona`
  - In `custom/app/models/custom/concerns/inbox.rb` (loaded via `Inbox.include_mod_with('Concerns::Inbox')`):
    ```ruby
    module Custom::Concerns::Inbox
      extend ActiveSupport::Concern
      included do
        has_one :scout_inbox, class_name: 'ScoutInbox', dependent: :destroy
        has_one :scout, through: :scout_inbox
      end
    end
    ```
