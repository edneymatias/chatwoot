# Quickstart: Validating the Scout Funnel Stage Qualification Gate

Manual, end-to-end validation of the acceptance scenarios in `spec.md`. Assumes the container stack
is already running (`docker compose up -d`) per `CLAUDE.md`.

## Prerequisites

1. An account with a Scout configured (Super Admin seed data or an existing dev account works).
2. Via the existing Kanban/Scout UI (no new UI ships with this feature):
   - Configure at least 3 pipeline stages (e.g. `New`, `Qualified`, `Unqualified`), with `Qualified`
     set as the Scout's `qualified_stage_id` and `Unqualified` as `unqualified_stage_id`. Set a
     purpose description on `Qualified` via the funnel stage description editor (e.g. "Lead has
     confirmed budget and timeline; ready for a human sales rep").
   - Add at least one `PipelineStageRequiredField` on `Qualified` (e.g. an opportunity custom
     attribute `Timeline`) whose definition has an `attribute_description` filled in (e.g. "When
     the prospect expects to make a purchase decision").
   - Add at least one `ScoutRequiredField` on the Scout (e.g. an opportunity custom attribute
     `Budget`, also with an `attribute_description` filled in) — this is the *global* qualification
     requirement, independent of the stage's own field.
   - Set the Scout's `handover_team_id` to an existing team.
   - Leave a second stage (e.g. `Unqualified`) without a description, to verify omission.
3. Have a conversation with an existing `Opportunity` linked to it (via `origin_conversation_id`),
   currently sitting in `New`.

## Scenario 1 — Stage catalog reaches the prompt (User Story 1)

- Trigger a Scout turn (send a message in the conversation, or use the Scout playground).
- Inspect the system instructions passed to the LLM (log line or debugger breakpoint in
  `AgentRunner#build_system_instructions` / `SystemPromptsService#build`).
- **Expected**: the prompt includes a funnel section naming `New`, `Qualified` (labeled qualified,
  with its configured purpose description attached), `Unqualified` (labeled unqualified, with no
  description line since none was configured), the `Timeline` requirement for `Qualified` (with its
  `attribute_description`), and `Budget` listed separately as a Scout-wide qualification
  requirement (with its own `attribute_description`).

## Scenario 2 — Qualification blocked without global requirement (User Story 2)

- Without setting `Budget` on the opportunity, call `move_opportunity_stage(stage_id: <Qualified>)`
  (directly via the tool test harness, or by asking the agent to qualify the lead in conversation).
- **Expected**: the opportunity's `pipeline_stage_id` is unchanged in the database; the tool returns
  a message naming `Budget` as missing; no team/assignee is set on the conversation; no
  `bot_handoff!` occurred.
- Set `Budget` (and `Timeline`, satisfying the stage's own requirement) on the opportunity, retry
  the same call.
- **Expected**: the move succeeds; `pipeline_stage_id` is now `Qualified`.

## Scenario 3 — Automatic handoff, exactly once (User Story 3 + clarification)

- Immediately after Scenario 2's successful move: check the conversation's `team_id` (matches the
  Scout's `handover_team_id`), its status (moved out of `pending` via `bot_handoff!`), and that no
  separate `handover_to_human` tool call was needed.
- Call `move_opportunity_stage(stage_id: <Qualified>)` again (redundant, opportunity already there).
- **Expected**: call succeeds (no-op for the stage), but no second transfer note is created and
  `bot_handoff!`/team assignment logic does not re-run a second time.

## Scenario 4 — Forward move with unmet stage requirement doesn't crash (User Story 4)

- Create a second stage between `New` and `Qualified` (e.g. `Contacted`) with its own required
  field not yet filled on the opportunity.
- From `New`, call `move_opportunity_stage(stage_id: <Contacted>)` without filling that field.
- **Expected**: no exception surfaces to `AgentRunner`; the tool returns a descriptive
  missing-fields message; the conversation is **not** kicked into the generic
  `perform_fail_safe_handoff` path; `pipeline_stage_id` is unchanged.
- Repeat the same missing-field scenario via `manage_opportunity(action: 'update', stage_id: <Contacted>)`.
- **Expected**: identical outcome/message shape — confirms FR-008 (no bypass via the other tool).

## Scenario 5 — Disqualification doesn't close the deal (User Story 5)

- From any stage, call `move_opportunity_stage(stage_id: <Unqualified>)`.
- **Expected**: `pipeline_stage_id` becomes `Unqualified`; `status` remains `open`; no handoff
  fires; no `lost_reason` field exists on the tool anymore (attempting to pass one is simply
  ignored/rejected by the tool's parameter schema, not processed).

## Regression checks

- A backward move (e.g. `Qualified` → `New`) and a lateral move between same-position stages still
  succeed exactly as before this feature, with no new required-field enforcement applied.
- `manage_opportunity(action: 'create', ...)` still creates directly into the resolved initial
  stage with no required-field enforcement (FR-013).
- `handover_to_human` called directly by the agent (outside of a qualification event) still assigns
  team/assignee, calls `bot_handoff!` only if pending, creates a transfer note only if `reason` is
  given, and generates contact memory only if `scout.feature_memory?` — identical to pre-feature
  behavior.

Automated coverage for all of the above lives in `custom/spec/services/custom/scout/` (see
`plan.md`'s Project Structure for the specific spec files touched/added); run with:

```
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/
```
