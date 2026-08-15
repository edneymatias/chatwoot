# Quickstart: Validating Opportunity-Triggered Automations

## Overview

This guide details the validation workflow to verify that opportunity lifecycle events correctly trigger automation rules, evaluate conditions, execute actions across Opportunity, Contact, and Conversation entities, safely handle missing conversations, and avoid infinite loops.

---

## Prerequisites

Ensure the Docker / Podman development environment is running:
```bash
docker compose up -d
```

---

## Scenario 1: Opportunity Creation Automation (Immediate Assignee Assignment)

1. **Setup Automation Rule**:
   - Go to **Settings > Automations** (`/app/accounts/{accountId}/settings/automation`).
   - Click **Add Rule**.
   - Event: Select **Opportunity Created** (`opportunity_created`).
   - Conditions: `value` greater than `5000`.
   - Actions: `update_opportunity_assignee` → Select User (e.g. Agent A).
   - Save the rule.

2. **Trigger**:
   - Create a new opportunity with `value = 6000` via UI (Quick Create or Modal) or API.

3. **Verify**:
   - The created opportunity immediately shows Agent A as the assignee.
   - Audit logs show the automation execution without errors.

---

## Scenario 2: Opportunity Stage Transition with Cross-Entity Actions & Fallback

1. **Setup Automation Rule**:
   - Event: **Opportunity Stage Changed** (`opportunity_stage_changed`).
   - Conditions: `from_pipeline_stage_id` = Stage 1 ("Qualification"), `pipeline_stage_id` = Stage 2 ("Proposal").
   - Actions:
     - `update_contact_custom_attribute` → `vip: true`
     - `add_private_note` → "Deal moved to proposal stage automatically."

2. **Test With Linked Conversation**:
   - Open Kanban board or Opportunity details for a deal linked to Conversation #100.
   - Drag card from Stage 1 to Stage 2.
   - **Verify**: Contact has `vip: true` set and Conversation #100 has a new internal note posted by System / Automation Bot.

3. **Test Without Linked Conversation (Graceful Fallback)**:
   - Move a standalone opportunity (no linked conversation) from Stage 1 to Stage 2.
   - **Verify**: Contact has `vip: true` set and the transition completes smoothly with no background job errors or failures.

---

## Scenario 3: Opportunity Won / Lost Workflows & Loop Prevention

1. **Setup Rule 1 (On Won)**:
   - Event: **Opportunity Won** (`opportunity_won`).
   - Action: `update_opportunity_stage` → "Closed Won" stage.

2. **Setup Rule 2 (On Stage Changed to Closed Won)**:
   - Event: **Opportunity Stage Changed** (`opportunity_stage_changed`) where `pipeline_stage_id` = "Closed Won".
   - Action: `update_contact_attribute` → `company: "Customer Inc"`.

3. **Trigger**:
   - Mark an opportunity as `won`.

4. **Verify**:
   - Status updates, stage updates, and contact updates occur cleanly.
   - No infinite looping or job queue explosion occurs due to `Current.executed_by` tracking.

---

## Automated Backend Specs Verification

Run the RSpec test suite inside the container:
```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/automation_rules/opportunity_action_service_spec.rb custom/spec/listeners/custom/automation_rule_listener_spec.rb
```
