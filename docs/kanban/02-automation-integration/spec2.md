# Phase 2: Automation Integration — `create_opportunity` Automation Action

**Depends on**: Phase 1 (`Opportunity`, `PipelineStage` models, `custom/` tree, `include_mod_with`/`prepend_mod_with` wiring must already work)
**Feeds**: Phase 3 (frontend needs the action to appear in the Automation Rules UI dropdown), Phase 4 (n/a)

## Context

Rather than building a bespoke "which label triggers an Opportunity" settings screen, this phase reuses Chatwoot's existing `AutomationRule` engine. Admins configure trigger event + conditions (e.g., "conversation created" + "label contains X") + action entirely through the existing Automation Rules UI — the only change is registering a brand-new action, `create_opportunity`, alongside the existing ones (`add_label`, `assign_agent`, etc.).

This is implemented with zero edits to `app/models/automation_rule.rb` or `app/services/automation_rules/action_service.rb`, using the same `prepend_mod_with`/`include_mod_with` extension mechanism validated in Phase 1.

## Dev Environment

All commands run inside the `rails` container: `docker compose exec rails <command>` (no host Ruby toolchain — see Phase 1's Dev Environment note).

## Functional Requirements

**FR-001**: `custom/app/models/custom/automation_rule.rb` MUST define `module Custom::AutomationRule` that overrides/extends `actions_attributes` to append `create_opportunity` to the existing list (`%w[send_message add_label remove_label ... add_private_note]`). This module is picked up automatically because `app/models/automation_rule.rb` already ends with `AutomationRule.prepend_mod_with('AutomationRule')` — no edit to that file.

**FR-002**: `custom/app/services/custom/automation_rules/action_service.rb` MUST define `module Custom::AutomationRules::ActionService` implementing `create_opportunity(params)`, matching the exact dynamic-dispatch contract used by `AutomationRules::ActionService#perform` (iterates `@rule.actions`, calls `send(action[:action_name], action[:action_params])`). `AutomationRules::ActionService` MUST be updated to call `prepend_mod_with('AutomationRules::ActionService')` at the bottom of the class body — this is the one small addition required to `app/services/automation_rules/action_service.rb` itself, since that class currently has no extension seam (unlike `AutomationRule` and `Contact`, which already call `prepend_mod_with`/`include_mod_with`). Confirm this is the only necessary core-file edit in this phase before implementing.

**FR-003**: `create_opportunity(params)` behavior:
- Runs in the context of `@conversation` (same as `add_label`/`remove_label`, available as an instance var on `ActionService`).
- `params` (`action_params`) MUST support: `pipeline_stage_id` (required — which stage the new Opportunity starts in) and optional `title_template` (string, defaults to conversation's contact name + creation date if blank, e.g. `"#{@conversation.contact.name} - #{Date.current}"`).
- Creates one `Opportunity` with `account: @conversation.account`, `contact: @conversation.contact`, `pipeline_stage_id: params[:pipeline_stage_id]`, `origin_conversation: @conversation`, `status: :open`.
- MUST be idempotent per conversation: if an `Opportunity` already exists with the same `origin_conversation_id`, do NOT create a duplicate — skip silently (automation rules can re-fire on subsequent events for the same conversation, e.g. multiple label additions).
- Any `ActiveRecord::RecordInvalid` (e.g., contact missing) MUST propagate normally so it's caught and logged by the existing per-action `rescue StandardError => e; ChatwootExceptionTracker.new(e, ...).capture_exception` wrapper in `AutomationRules::ActionService#perform` — no custom rescue needed inside `create_opportunity`.

**FR-004**: The action MUST be usable with any existing `AutomationRule` trigger event (`conversation_created`, `conversation_updated`, `message_created`, etc.) and any existing condition set (including `label_added`-equivalent conditions already supported by the automation condition filters) — no new trigger or condition type is introduced in this phase.

**FR-005**: I18n: add the new action's label (e.g. "Create Opportunity") to `config/locales/en.yml` under the automation actions i18n namespace (mirrors existing entries for `add_label`, `assign_agent`, etc.) — required for Phase 3's dropdown to render a human label instead of a raw key.

## Out of Scope (this phase)

- Any Vue-side rendering of the new action's parameter picker (that's Phase 3 — this phase only requires the action to be dispatchable and to appear in the backend `actions_attributes` list/API response).
- Multi-pipeline routing logic (single implicit pipeline per account, same as Phase 1).

## Completion Criteria

No new UI is introduced in this phase (the dropdown entry appears automatically once Phase 3 renders it, but the mechanism itself is testable headlessly now).

1. **Action is registered** (FR-001):
   ```
   docker compose exec rails bundle exec rails runner "puts AutomationRule.new.actions_attributes.include?('create_opportunity')"
   ```
   Must print `true`.

2. **Prepend wiring works without core-file behavior change** (FR-002): confirm `AutomationRules::ActionService.instance_methods.include?(:create_opportunity)` via `docker compose exec rails bundle exec rails runner "..."`, and confirm the *only* diff introduced to `app/services/automation_rules/action_service.rb` is the one `prepend_mod_with` line (verify with `git diff app/services/automation_rules/action_service.rb` on the host — the repo is bind-mounted into the container, so `git diff` works identically on either side — should show a single added line).

3. **End-to-end action execution** (FR-003) — via `docker compose exec rails rails console`:
   ```ruby
   account = Account.first
   conversation = account.conversations.first
   stage = account.pipeline_stages.first || account.pipeline_stages.create!(name: "Leads Recebidos", position: 0)
   rule = account.automation_rules.create!(
     name: "Test", event_name: "conversation_created", conditions: [], account: account,
     actions: [{ action_name: "create_opportunity", action_params: { pipeline_stage_id: stage.id } }]
   )
   AutomationRules::ActionService.new(rule: rule, account: account, conversation: conversation).perform
   puts Opportunity.where(origin_conversation: conversation).count   # expect 1

   # re-run to prove idempotency (FR-003)
   AutomationRules::ActionService.new(rule: rule, account: account, conversation: conversation).perform
   puts Opportunity.where(origin_conversation: conversation).count   # still 1, not 2
   ```

4. **Automated regression test**: `docker compose exec rails bundle exec rspec spec/services/automation_rules/action_service_spec.rb` (extend with a `create_opportunity` context if not already covered) and `docker compose exec rails bundle exec rspec spec/models/automation_rule_spec.rb` — both green.

5. **I18n present** (FR-005): `docker compose exec rails bundle exec rails runner "puts I18n.t('automation.action.create_opportunity.label', default: 'MISSING')"` (adjust key path to match the actual `en.yml` structure used by existing actions) must NOT print `MISSING`.
