# Research: Realtime Sync & Menu/Route Wiring

## 1. Account-level ActionCable channel to reuse

**Decision**: Reuse the existing `account_#{account.id}` pubsub token/stream — the same one `RoomChannel#ensure_stream` already subscribes every logged-in agent/admin to (`app/channels/room_channel.rb`), and the same one `ActionCableListener#account_token` already broadcasts `contact.updated`/`contact.created`/`contact.merged`/`contact.deleted` to (`app/listeners/action_cable_listener.rb:216-217, 158-171`).

**Rationale**: `contact_updated` is the closest existing precedent — an account-wide broadcast (not scoped to a specific conversation's inbox members) delivered over the same stream every session already listens on. Reusing it means zero new `ActionCable::Channel` subclass and zero new frontend subscription — the dashboard's `ActionCable.js` helper already consumes this stream via its `this.events` dispatch table.

**Alternatives considered**: A dedicated `OpportunityChannel` — rejected; out of scope per spec's Assumptions and adds a subscription the frontend would have to separately manage for no benefit over the channel already open on every session.

## 2. Backend broadcast mechanism (after_commit vs. dispatcher/listener)

**Decision**: A plain `after_commit` callback directly on `custom/app/models/opportunity.rb`, calling `ActionCableBroadcastJob.perform_later(["account_#{account_id}"], 'opportunity_updated', payload)` directly — **not** routed through `Rails.configuration.dispatcher` / `Events::Types` / `ActionCableListener`.

**Rationale**: The core dispatcher/listener pattern (`app/dispatchers`, `app/listeners/action_cable_listener.rb`, `app/services/events/types.rb`) exists so a *single* domain event can fan out to multiple independent listeners (webhooks, automation rules, notifications, ActionCable, etc.). Opportunity has no other listener that needs to react to this event today — only the ActionCable broadcast is required (FR-001). Wiring it through the shared dispatcher would require adding a new `Events::Types` constant and a new method to the **core** `ActionCableListener` class and registering interest — three core-file edits for a fan-out mechanism nothing else consumes. A direct `after_commit` on our own `custom/` model calling the existing (unmodified) `ActionCableBroadcastJob` needs **zero core-file edits**, matches Constitution Principle I's "prefer additive, isolated changes over edits to shared core files," and Principle II's "smallest change that satisfies the actual requirement." `ActionCableBroadcastJob` is called as-is (not subclassed or edited) — its `prepare_broadcast_data` only special-cases the `CONVERSATION_UPDATE_EVENTS` list and passes any other event's data straight through, so `opportunity_updated` needs no change there either.

**Alternatives considered**: Dispatcher + new `ActionCableListener#opportunity_updated` method — rejected per above (unnecessary core touch for a single consumer). A dedicated `custom/app/listeners/opportunity_action_cable_listener.rb` subscribed via `SyncDispatcher#listeners` — also rejected: `SyncDispatcher#listeners` is a hardcoded array in a core file with no `prepend_mod_with` extension point (unlike `AsyncDispatcher`, which already has one) — adding a custom listener there would still require a core-file edit for no benefit over a direct `after_commit`.

## 3. Broadcast trigger scope (which field changes fire the event)

**Decision**: Broadcast on every `Opportunity` create and update (`after_commit on: %i[create update]`), not filtered to a subset of "board-relevant" fields.

**Rationale**: Matches the established convention (`Conversation#dispatch_conversation_updated_event`, called from `execute_after_update_commit_callbacks` on any tracked update) rather than hand-picking fields — simpler, and avoids a second bug class where a card silently misses an update because a field wasn't in the allow-list.

## 4. Payload shape

**Decision**: `{ id:, pipeline_stage_id:, status:, contact_id:, assignee_id:, updated_at:, account_id: }` — a plain hash built inline in the model callback, not a `push_event_data`-style method (Opportunity has none today and the spec's FR-002 minimum field list doesn't warrant one).

**Rationale**: Matches FR-002's minimum field list exactly; `account_id` is added because every other `account_token`-broadcast payload in `action_cable_listener.rb#broadcast` merges `account_id: account.id` in, and the frontend action-cable helper conventionally keys off it for routing/logging.

## 5. Frontend event handling

**Decision**: `actionCable.js` gains one entry, `'opportunity_updated': this.onOpportunityUpdated`, inserted immediately adjacent to the existing `'conversation.updated': this.onConversationUpdated,` line. The handler dispatches a single existing Phase 3 Vuex action (`opportunities/updateOpportunity` — mutates `cardsById` in place and moves the id between `cardIdsByStage` arrays if `pipeline_stage_id` changed), reusing the mutation Phase 3 already built for optimistic drag-drop updates rather than adding new mutation logic.

**Rationale**: Directly satisfies FR-002/FR-004; keeps the diff to actionCable.js to the smallest possible insertion (one map entry + one handler method), consistent with Principle II.

## 6. Audit of files already wired ahead of this phase

**Finding**: A diff against `develop` (`git diff develop...HEAD --stat`) shows 3 of the 5 files spec4.md anticipated needing wiring were **already committed** in the Phase 3 commit (`36848952b`): `Sidebar.vue` (Settings › Pipeline Stages entry only — no main-nav board entry yet), `settings.routes.js` (Pipeline Stages route), and `store/index.js` (both Vuex modules registered). Additionally, files touched during the earlier automation-integration work (`0a46d2b15`, `9c7137073`) that are in scope per this phase's expanded FR-014 are also already committed: `featureFlags.js`, `composables/useAutomationValues.js`, `helper/automationHelper.js`, `routes/dashboard/settings/automation/constants.js`, `i18n/locale/en/index.js`, `i18n/locale/en/automation.json`, `i18n/locale/en/settings.json`.

**Still genuinely unwired** (require new edits in this phase): `dashboard.routes.js` (no route exists yet for `KanbanBoard.vue`), `actionCable.js` (no `opportunity_updated` entry), and `Sidebar.vue` (missing the main-navigation entry to the board itself — only the settings sub-entry exists).

**Rationale/impact**: The sync script's manifest (FR-013/FR-014) must include anchor+insert definitions for the *already-applied* edits too (so `--check` on a clean checkout reports them present, and re-running `--apply` after a hypothetical revert restores them) — not only the 2 genuinely-new files. This is a documentation/manifest-completeness task, not new application code, for those 7 already-committed files.

## 7. Board route naming & permissions

**Decision**: New route `name: 'opportunities_index'`, `path: frontendURL('accounts/:accountId/opportunities')`, `meta: { featureFlag: FEATURE_FLAGS.OPPORTUNITIES, permissions: ['administrator', 'agent', 'custom_role'] }`, modeled on `campaigns.routes.js`'s `meta` shape.

**Rationale**: `OpportunityPolicy#index?` allows any `account_user` (scoped further per-record), so the board itself is agent-reachable, unlike the admin-only Pipeline Stages settings screen (`pipeline_stages_index`, already committed with `permissions: ['administrator']`). Naming follows the existing `<feature>_index` convention (`pipeline_stages_index`, `campaigns_ongoing_index`).

## 8. Sync script design (`bin/sync-custom-module-hooks`)

**Decision**: A single Ruby script under `bin/`, manifest as a top-level array of hashes (`file:`, `anchor:`, `insert:`, optional `indent:`), run via `bin/sync-custom-module-hooks --check|--apply`. For each manifest entry: read the target file, check whether `insert` is already present (idempotency — FR-011) — if so, skip; else locate `anchor` via exact string match — if not found, record a failure (file + anchor) and, in `--apply` mode, skip only that file's remaining entries while continuing to process other files, then exit non-zero at the end if any failures were recorded (FR-006/FR-012). `--check` performs the same detection but never writes.

**Rationale**: Matches FR-004–FR-013 exactly; a flat array-of-hashes manifest (vs. YAML/JSON) keeps anchor definitions in the same file as the apply logic for easier one-PR review (FR-013), while still being trivially reviewable as data.

**Testing pattern precedent**: Backend broadcast tests should follow `spec/listeners/action_cable_listener_spec.rb`'s existing convention — `expect(ActionCableBroadcastJob).to receive(:perform_later).with(...)` — rather than configuring the ActionCable test adapter, since that's the pattern already used for every other account/contact-level broadcast in this codebase.
