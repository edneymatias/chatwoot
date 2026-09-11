# Quickstart: Validating Scout Follow-Up Nudges and Rescue Handoff

Validates the end-to-end flow described in `spec.md` (User Stories 1–4) against a running dev
stack. See `data-model.md` for field semantics and `contracts/scouts-api.md` for the API shape.

## Prerequisites

- Stack running: `docker compose up -d`
- A Scout configured on an account with at least one linked inbox (existing dev seed data, or via
  Super Admin → Accounts → Seed)
- An open `Opportunity` linked to a `pending` conversation on that Scout's inbox

## 1. Configure the automation

Via the Scout settings API/UI, set:
- `follow_up_delays_hours`: a short test-friendly sequence, e.g. `[0, 0, 0]` is invalid (must be
  strictly ascending positive integers) — use fractional-hour-equivalent testing instead by
  freezing time in specs, or for manual UI testing, temporarily back-date the conversation's
  `last_activity_at` rather than waiting real hours.
- `rescue_stage_id`: an existing pipeline stage on the same account, distinct from the opportunity's current stage.

## 2. Trigger nudge 1

```
docker compose exec rails bundle exec rails runner "
  convo = Conversation.find(<id>)
  convo.update!(last_activity_at: 3.hours.ago) # past the default 2h threshold
"
docker compose exec rails bundle exec rails runner "Custom::Scout::FollowUpJob.perform_now"
```

**Expected**: the conversation receives one new outgoing, non-private message
(`content_attributes['scout_follow_up'] == true`), conversation stays `pending`, opportunity stage
unchanged.

## 3. Trigger nudge 2

Back-date `last_activity_at` past the second threshold (default 12h) and re-run the job.

**Expected**: a second nudge is sent; still no stage change, still `pending`.

## 4. Trigger rescue handoff

Back-date `last_activity_at` past the third/final threshold (default 24h) and re-run the job.

**Expected**:
- Opportunity's `pipeline_stage_id` == the Scout's `rescue_stage_id`
- Conversation received a public message from `scout.follow_up_handoff` i18n key (not the generic `scout.handoff` text) and a private note referencing the opportunity
- Conversation is no longer `pending` (`bot_handoff!` applied)

## 5. Verify the race guards

- Reply as the contact (or assign a human) to a `pending` conversation that has already crossed a
  threshold, then run the job again before any nudge would fire — confirm no nudge/handoff is
  sent.
- With the response auditor feature flag on, simulate a human reply landing mid-audit (see
  `custom/spec/services/custom/scout/agent_runner_spec.rb` for the automated version of this
  scenario) — confirm no duplicate reply and no handoff.

## 6. Verify business hours guard

Set the inbox's working hours to exclude the current time, cross a threshold, run the job.

**Expected**: no message sent this run; running the job again after moving the current time (or
working hours) back into range delivers the pending nudge/handoff as if no cycle had been missed.

## 7. Verify the Kanban badge

Open the deal board for the opportunity used above:
- While its active conversation is `pending` with the Scout: card shows the "Scout" badge.
- After the rescue handoff (or any manual handoff) in step 4: reload the board — badge is gone.

## 8. Automated verification

```
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/jobs/custom/scout/follow_up_job_spec.rb \
  custom/spec/services/custom/scout/agent_runner_spec.rb \
  custom/spec/models/scout_spec.rb \
  custom/spec/controllers/api/v1/accounts/scouts_controller_spec.rb \
  spec/configs/schedule_spec.rb

docker compose exec vite pnpm test -- KanbanCard
```
