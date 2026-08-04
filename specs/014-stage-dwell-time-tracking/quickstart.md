# Quickstart: Stage Dwell-Time Tracking

Validates the feature end-to-end against a running dev stack
(`docker compose up -d`; see project `CLAUDE.md` for the full container
workflow).

## Prerequisites

- Dev stack running with at least one account that has the Kanban feature
  enabled and at least two pipeline stages (`PipelineStage.seed_defaults_for!`
  creates two by default: "Leads Recebidos", "Em Contato").
- Migrations applied: `docker compose exec rails bundle exec rails db:migrate`.

## Scenario 1: Dwell time appears on creation (User Story 1)

1. Create an opportunity via the kanban board UI (or
   `docker compose exec rails bundle exec rails runner "Opportunity.create!(...)"`).
2. Open the kanban board and locate the card.
3. **Expect**: the card shows a dwell-time badge reflecting a few
   seconds/minutes elapsed, not the opportunity's full age.

## Scenario 2: Dwell time resets on stage move, ignores other edits (User Story 1)

1. Wait a few minutes, then edit the opportunity's title only (no stage
   change) via the UI.
2. Reload the board. **Expect**: the badge is unchanged by the title edit.
3. Drag the opportunity to a different stage.
4. Reload the board. **Expect**: the badge now shows a dwell time close to
   zero, timed from the stage move, not from the opportunity's original
   creation.
5. Verify in Rails console:
   `docker compose exec rails bundle exec rails console` ->
   `Opportunity.find(<id>).stage_changes.order(:changed_at).pluck(:from_stage_id, :to_stage_id, :changed_at)`
   should show two rows: the initial creation transition and the move.

## Scenario 3: Configure a staleness threshold (User Story 2)

1. In Pipeline Stage settings, edit a stage and set "stale after N days" to
   e.g. `1`.
2. Leave a second stage's threshold empty.
3. **Expect**: saving succeeds; reopening the edit form shows the persisted
   value for the first stage and an empty field for the second.

## Scenario 4: Alert styling triggers correctly (User Story 3)

1. For the stage configured with a 1-day threshold in Scenario 3, use Rails
   console to backdate an opportunity's most recent transition beyond the
   threshold:
   `docker compose exec rails bundle exec rails runner "oc = Opportunity.find(<id>).stage_changes.order(:changed_at).last; oc.update!(changed_at: 2.days.ago)"`
2. Reload the kanban board. **Expect**: that opportunity's badge now renders
   in the alert (amber) style; opportunities in the same stage still within
   the threshold, and any opportunity in the unconfigured second stage
   (regardless of dwell time), keep the neutral badge style.

## Expected outcome

All four scenarios pass without needing any data backfill or migration of
pre-existing opportunities, per the spec's Assumptions section.
