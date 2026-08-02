# Quickstart: Stage Transition Rules

Verify inside the `rails`/`vite` containers per `CLAUDE.md`. Assumes the stack is already up
(`docker compose up -d`) and at least two `PipelineStage`s and one `Contact` exist for the test
account (seed via `bundle exec rails db:seed` if needed).

## Prerequisites

- An account with at least two pipeline stages (e.g. "Leads Recebidos" at position 1, "Qualified"
  at position 2).
- One `opportunity_attribute`-model custom attribute definition (e.g. `budget`, currency type).

## 1. Create an opportunity-model custom attribute

Dashboard → Settings → Custom Attributes → Add attribute → set "Applies to" to the new
"Opportunity" option → save. Confirm it appears in the Attributes list filtered by that model.

Or via Rails console (`docker compose exec rails bundle exec rails console`):
```ruby
account.custom_attribute_definitions.create!(
  attribute_display_name: 'Budget',
  attribute_key: 'budget',
  attribute_display_type: 'currency',
  attribute_model: 'opportunity_attribute'
)
```

## 2. Configure a lane's required fields

Dashboard → Settings → Pipeline Stages → edit "Qualified" → check "Budget" and toggle "Requires
deal value" → save. Re-open "Qualified"'s settings and confirm both are still checked.

## 3. Forward move with missing fields is blocked client-side

Open the Kanban board. Drag a card with no budget/value set from "Leads Recebidos" into
"Qualified". Expect: `StageTransitionRequirementsModal` opens instead of the card landing
immediately; "Budget" and deal value are shown as required (asterisked); submitting without them
is blocked. Fill both, submit — the card lands in "Qualified" and the modal closes.

## 4. Forward move with satisfied fields is immediate

Set the same card's budget and value (e.g. via the "complete fields" action or by editing
directly), then drag another already-qualified card forward. Expect: no modal, immediate move.

## 5. Backward move is never blocked

Drag the same card (still missing nothing, or deliberately with fields cleared) backward from
"Qualified" to "Leads Recebidos". Expect: no modal, immediate move, regardless of field state.

## 6. Direct API bypass returns structured `422`

```bash
curl -X PATCH \
  -H "Content-Type: application/json" \
  -H "api_access_token: <agent token>" \
  -d '{"opportunity": {"pipeline_stage_id": <qualified_stage_id>}}' \
  http://localhost:3000/api/v1/accounts/<account_id>/opportunities/<opportunity_id_missing_fields>
```
Expect `422` with body containing `missing_required_fields.custom_attribute_keys` including
`"budget"` and `missing_required_fields.requires_value: true`.

## 7. Creation is exempt but stage-aware

Dashboard → Opportunities → New → select "Qualified" as the starting stage. Expect: "Budget" field
(and deal value) render inline on the creation form. Submit without filling them — expect the
opportunity is created successfully in "Qualified".

## 8. "Complete fields" backfill action

Move a card backward into "Qualified" from a later stage (or reconfigure "Qualified" to require a
field the card doesn't have), leaving it non-compliant with its current stage. Expect: the card
shows a "complete fields" action. Use it, fill the missing field, submit — expect the opportunity
updates and stays in "Qualified" (no stage change).

## 9. Lint/spec gates

```bash
docker compose exec rails bundle exec rubocop -a
docker compose exec rails bundle exec rspec spec/models/opportunity_spec.rb spec/models/pipeline_stage_spec.rb spec/models/pipeline_stage_required_field_spec.rb spec/requests/api/v1/accounts/opportunities_controller_spec.rb spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb spec/requests/api/v1/accounts/pipeline_stage_required_fields_controller_spec.rb
docker compose exec vite pnpm eslint
docker compose exec vite pnpm test
```
