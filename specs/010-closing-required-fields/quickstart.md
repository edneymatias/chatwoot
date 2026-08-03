# Quickstart: Validating Closing Required Fields

Prerequisites: stack running via `docker compose up -d` (see project `CLAUDE.md`); an account with
at least one opportunity attribute custom attribute definition and one open opportunity.

## 1. Configure a closing requirement (User Story 2)

```bash
docker compose exec rails bundle exec rails runner "
  account = Account.first
  definition = account.custom_attribute_definitions.opportunity_attribute.first!
  PipelineClosingRequiredField.create!(account: account, custom_attribute_definition: definition, outcome: :lost)
"
```

Expected: row created; a second `create!` with the same `account`/`definition`/`outcome: :lost`
raises a uniqueness validation error; the same `definition` with `outcome: :won` succeeds
(independent lists, per FR-003).

## 2. Attempt to close without the required attribute (User Story 1)

```bash
docker compose exec rails bundle exec rails runner "
  account = Account.first
  opp = account.opportunities.where(status: :open).first!
  opp.update(status: :lost)
  puts opp.errors.full_messages
  puts opp.missing_required_fields.inspect
"
```

Expected: `update` returns `false`; `errors.full_messages` includes the closing-requirement
message; `missing_required_fields[:custom_attribute_keys]` includes the configured attribute's key.

Via the API (matches the FR-006/contract behavior end-to-end):

```bash
curl -X PATCH "http://localhost:3000/api/v1/accounts/1/opportunities/<id>" \
  -H "Content-Type: application/json" -H "api_access_token: <token>" \
  -d '{"opportunity": {"status": "lost"}}'
```

Expected: `422` with `missing_required_fields.custom_attribute_keys` containing the required key.

## 3. Supply the missing attribute and retry (SC-002)

```bash
curl -X PATCH "http://localhost:3000/api/v1/accounts/1/opportunities/<id>" \
  -H "Content-Type: application/json" -H "api_access_token: <token>" \
  -d '{"opportunity": {"status": "lost", "custom_attributes": {"<attribute_key>": "budget"}}}'
```

Expected: `200`, opportunity's `status` is now `lost`.

## 4. Reopen is never blocked (User Story 3 / SC-004)

```bash
curl -X PATCH "http://localhost:3000/api/v1/accounts/1/opportunities/<id>" \
  -H "Content-Type: application/json" -H "api_access_token: <token>" \
  -d '{"opportunity": {"status": "open"}}'
```

Expected: `200` regardless of which attributes are present — no `missing_required_fields` check
runs on this transition (FR-007).

## 5. End-to-end UI check (once frontend pieces land)

1. In the dashboard, open the pipeline settings screen and add a required attribute for "lost".
2. On the Kanban board, drag a card to the "lost" status without filling that attribute.
3. Confirm `ClosingRequirementsModal` opens showing only the missing attribute (via
   `OpportunityRequiredFieldsForm`).
4. Fill it in and submit; confirm the card moves to "lost" and the modal closes.
5. Reopen the same card back to an open stage; confirm no modal appears.

See [contracts/closing-required-fields-api.md](./contracts/closing-required-fields-api.md) for full
request/response shapes and [data-model.md](./data-model.md) for validation semantics.
