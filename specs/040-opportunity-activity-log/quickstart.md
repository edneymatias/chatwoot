# Quickstart Validation Guide: Opportunity Activity Log

**Feature**: Opportunity Activity Log  
**Branch**: `040-opportunity-activity-log`  
**Date**: 2026-08-17  

---

## 1. Prerequisites & Environment Setup

Ensure the Docker / Podman dev environment is running:
```bash
docker compose up -d
```

Run the database migration and backfill:
```bash
docker compose exec rails bundle exec rails db:migrate
```

Audit and ensure wiring hooks are synced:
```bash
docker compose exec rails ruby bin/sync-custom-module-hooks --check
```

---

## 2. Backend Event Capture Verification

### Scenario A: Lifecycle Event Recording in Rails Console
Run in terminal:
```bash
docker compose exec rails bundle exec rails console
```

Execute the following test snippet:
```ruby
account = Account.first
stage1 = account.pipeline_stages.first
stage2 = account.pipeline_stages.second
user = account.users.first

# 1. Test creation
opp = account.opportunities.create!(
  title: "Activity Log Test Deal",
  pipeline_stage: stage1,
  contact: account.contacts.first
)

# 2. Test stage change
opp.update!(pipeline_stage: stage2)

# 3. Test terminal state (won)
opp.update!(status: :won)

# 4. Verify activities recorded
activities = opp.activities.order(occurred_at: :asc)
puts "Recorded #{activities.count} activities:"
activities.each { |a| puts " - #{a.event_type} (actor: #{a.actor&.name || 'System'}, meta: #{a.metadata})" }
```

**Expected Outcome**:
- `opportunity_created` activity exists.
- `opportunity_stage_changed` activity exists with metadata `from_stage_id` and `to_stage_id`.
- `opportunity_won` activity exists.

---

## 3. API Endpoint Validation

Test the HTTP endpoint using `curl` or Rails request spec:
```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec spec/requests/api/v1/accounts/opportunities/activities_controller_spec.rb
```

**Expected Outcome**:
- Returns `200 OK` with JSON array of activities in reverse chronological order.

---

## 4. Frontend UI Validation

1. Log into Chatwoot dashboard (`http://localhost:3000`).
2. Navigate to the Kanban board (`/app/accounts/{id}/opportunities`).
3. Click on a deal card that has an active conversation to open `OpportunityConversationDrawer`.
4. In the drawer's top-left button group, verify the new Activity Log icon button appears.
5. Click the Activity Log button:
   - The conversation view swaps to the `OpportunityActivityLog` vertical timeline.
   - All lifecycle events (creation, stage moves, won/lost status, conversation links) are rendered with correct icons, labels, actors, and timestamps.
   - Any historical approximate items display the `(aproximado)` caveat badge.
6. Click the toggle button again:
   - The drawer swaps back to the Conversation view without reloading or losing state.

---

## 5. Automated Test Suite Validation

Run full backend and frontend lint and tests:
```bash
# Ruby RuboCop
docker compose exec rails bundle exec rubocop custom/

# RSpec
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/

# ESLint
docker compose exec vite pnpm eslint

# Frontend Specs
docker compose exec vite pnpm test
```
