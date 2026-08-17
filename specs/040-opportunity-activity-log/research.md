# Phase 0: Research & Technical Decisions

**Feature**: Opportunity Activity Log  
**Branch**: `040-opportunity-activity-log`  
**Date**: 2026-08-17  
**Status**: Completed  

---

## 1. Event Capture & Dispatch Architecture

### Decision
Implement `Custom::OpportunityActivityListener < BaseListener` in `custom/app/listeners/custom/opportunity_activity_listener.rb` and wire it into the asynchronous event bus via `Custom::AsyncDispatcher` (`custom/app/dispatchers/custom/async_dispatcher.rb`), which is prepended onto `AsyncDispatcher` using Chatwoot's existing `prepend_mod_with('AsyncDispatcher')` extension point. Capture conversation linkage directly in `OpportunityConversation` via an `after_create :record_activity` callback.

### Rationale
- `Opportunity` already broadcasts 5 discrete lifecycle events via `Rails.configuration.dispatcher`: `opportunity_created`, `opportunity_stage_changed`, `opportunity_won`, `opportunity_lost`, and `opportunity_reopened` with rich payload data (including `from_pipeline_stage_id` and `performed_by: Current.executed_by || Current.user`).
- `AsyncDispatcher` in core (`app/dispatchers/async_dispatcher.rb:27`) already includes `AsyncDispatcher.prepend_mod_with('AsyncDispatcher')`.
- Zero lines in `app/` or `enterprise/` are modified.
- `OpportunityConversation` is a fork-owned model (`custom/app/models/opportunity_conversation.rb`), making an `after_create` callback completely isolated and zero-overhead.

### Alternatives Considered
- *Overriding `Opportunity#save` / controller hooks directly*: Rejected because it bypasses background events, automations, and external triggers.
- *Creating a synchronous listener on `ActionCableListener`*: Rejected because activity audit logging should run as a standard async listener without interfering with websocket broadcasting.

---

## 2. Data Storage & Schema Design

### Decision
Create a dedicated table `ichatr_opportunity_activities` with the following schema:
- `id`: `bigint`, Primary Key
- `account_id`: `bigint`, not null, indexed, foreign key to `accounts` (cascade delete)
- `opportunity_id`: `bigint`, not null, indexed, foreign key to `ichatr_opportunities` (cascade delete)
- `event_type`: `string`, not null (`opportunity_created`, `opportunity_stage_changed`, `opportunity_won`, `opportunity_lost`, `opportunity_reopened`, `conversation_opened`)
- `actor_type`: `string`, nullable (polymorphic: `'User'`, `'AutomationRule'`)
- `actor_id`: `bigint`, nullable
- `metadata`: `jsonb`, not null, default: `{}`
- `occurred_at`: `datetime`, not null
- `created_at` / `updated_at`: `datetime`, not null

Indexes:
- `[:account_id, :opportunity_id, :occurred_at]` named `index_ichatr_opp_activities_on_acc_and_opp_and_occurred`
- `[:account_id]` named `index_ichatr_opportunity_activities_on_account_id`
- `[:actor_type, :actor_id]` named `index_ichatr_opportunity_activities_on_actor`

### Rationale
- Scoped strictly to account and opportunity for instant index-backed queries ordered by `occurred_at DESC`.
- Polymorphic actor supports human users, automation rules, and system tasks (`nil`).
- `jsonb` metadata allows storing unstructured/flexible context (stage IDs, conversation identifiers, approximate flags) without schema changes when adding future event types (e.g. SIP/ARI calls, tasks).

### Alternatives Considered
- *Reusing existing `audit_logs` table*: Rejected because `audit_logs` in core is geared towards admin audit trails, lacks opportunity-level indexing, and coupling with it creates upstream merge friction.
- *Relational normalization for metadata*: Rejected because different event types have distinct payloads; `jsonb` is native to PostgreSQL and allows flat key-value serialization.

---

## 3. One-Time Historical Backfill

### Decision
Execute direct SQL backfill within the migration `up` method:
1. `opportunity_created`: One activity per `ichatr_opportunities` row (`occurred_at = created_at`, `actor = nil`).
2. `conversation_opened`: One activity per `ichatr_opportunity_conversations` row joined with `conversations` to get `display_id` (`occurred_at = created_at`, `actor = nil`).
3. `opportunity_stage_changed`: One activity per `ichatr_opportunity_stage_changes` row (`occurred_at = changed_at`, `metadata = { from_stage_id, to_stage_id }`, `actor = nil`).
4. `opportunity_won` / `opportunity_lost`: One activity per terminal-state opportunity (`status = 1` or `2`), `occurred_at = COALESCE(closed_at, updated_at)`, `actor = nil`, `metadata = { from_stage_id: pipeline_stage_id, approximate: true }`.
5. `opportunity_reopened`: Not backfilled (derivation impossible from static snapshots).

### Rationale
- Pure SQL execution ensures instantaneous, transactional backfill on deployment without loading thousands of ActiveRecord objects in Ruby memory.
- `metadata.approximate: true` preserves honest audit data by explicitly signaling to UI that terminal dates are estimates.

### Alternatives Considered
- *Async rake task or background job*: Rejected because migration SQL is fast (<1s for tens of thousands of rows) and guarantees immediate availability on deployment without manual operator commands.

---

## 4. Backend API & Routing

### Decision
- Add route: `GET /api/v1/accounts/:account_id/opportunities/:opportunity_id/activities`
- Controller: `Api::V1::Accounts::Opportunities::ActivitiesController < Api::V1::Accounts::BaseController` (located in `custom/app/controllers/api/v1/accounts/opportunities/activities_controller.rb`).
- Query: `Current.account.opportunities.find(params[:opportunity_id]).activities.order(occurred_at: :desc)`.
- Serialization: Returns JSON array with `id`, `event_type`, `metadata`, `occurred_at` (epoch integer / ISO), and `actor` object (`{ id, name, type }` or `{ type: 'system' }`).
- Routing injection: Update `bin/sync-custom-module-hooks` to include the nested `resources :activities, only: [:index], module: :opportunities` inside `resources :opportunities`.

### Rationale
- Follows existing controller patterns (`OpportunitiesController`, `PipelineStagesController`).
- Reuses `Current.account` tenant scoping and existing Opportunity authorization policy.
- Strictly read-only (`index` action only).

---

## 5. Frontend UI & Interaction

### Decision
- Trigger: Add toggle button to `ButtonGroup` in `OpportunityConversationDrawer.vue` (gated by `isOpportunitiesFeatureEnabled`).
- Component: Create `app/javascript/dashboard/components-next/Opportunities/OpportunityActivityLog.vue` using Vue 3 Composition API `<script setup>` and Tailwind CSS.
- Store: Add `getActivities(opportunityId)` in `app/javascript/dashboard/api/opportunities.js` and `fetchActivities` in `app/javascript/dashboard/store/modules/opportunities/actions.js`.
- Add getter `opportunityByConversationId` in `app/javascript/dashboard/store/modules/opportunities/getters.js`.
- i18n: Add localization keys synchronously in `app/javascript/dashboard/i18n/locale/en/opportunities.json` and `app/javascript/dashboard/i18n/locale/pt_BR/opportunities.json`.

### Rationale
- Preserves 100% Tailwind utility styling (no scoped CSS, no custom CSS).
- Avoids touching core `SidepanelSwitch.vue` or upstream conversation components.
- Seamlessly swaps conversation body with activity timeline inside the drawer.
