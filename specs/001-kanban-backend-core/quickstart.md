# Quickstart: Validating Kanban Backend Core

This phase ships no UI. All validation runs inside the `rails` container per `CLAUDE.md`. Ensure
the stack is up first: `docker compose up -d`.

## 1. Migrations apply cleanly and reversibly

```bash
docker compose exec rails bundle exec rails db:migrate
docker compose exec rails bundle exec rails runner "puts ActiveRecord::Base.connection.table_exists?('matias_opportunities')"
docker compose exec rails bundle exec rails runner "puts ActiveRecord::Base.connection.table_exists?('matias_pipeline_stages')"
# both must print true
docker compose exec rails bundle exec rails db:rollback STEP=2
docker compose exec rails bundle exec rails db:migrate
# must succeed without error
```

## 2. `custom/` autoloading resolves (proves FR-001 wiring)

```bash
docker compose exec rails bundle exec rails runner "puts Opportunity"
docker compose exec rails bundle exec rails runner "puts PipelineStage"
# both must resolve without NameError
```

## 3. Model + association sanity (proves FR-002–FR-004, FR-011)

```bash
docker compose exec rails rails console
```
```ruby
account = Account.first
contact = account.contacts.first
stage = account.pipeline_stages.create!(name: "Leads Recebidos") # position auto-assigned
opp = Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: "Teste")
opp.persisted?                          # => true
contact.opportunities.include?(opp)     # => true, proves FR-011 without touching contact.rb
```

## 4. Lazy default-stage seeding (FR-005)

On an account with zero `PipelineStage` rows, call the `index` endpoint (or the equivalent
service/controller path) twice:

```bash
docker compose exec rails curl -s http://localhost:3000/api/v1/accounts/:id/pipeline_stages -H "..."
```

The first call must create exactly the two default stages; the second must return the same two,
with no duplicates.

## 5. Feature activation toggle (FR-012, clarified)

```ruby
account.disable_features!('opportunities')
# Opportunity/PipelineStage endpoints must stop responding as if active
account.enable_features!('opportunities')
# previously created stages/opportunities must still be present and usable, unchanged
```

## 6. Policy enforcement (FR-006)

```bash
docker compose exec rails bundle exec rspec spec/policies/opportunity_policy_spec.rb
```

Covers: admin (full access), assignee-agent (access), unrelated-agent-with-no-conversation-access
(denied).

## 7. API contract (FR-008, FR-009)

```bash
docker compose exec rails bundle exec rspec \
  spec/requests/api/v1/accounts/opportunities_controller_spec.rb \
  spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb
```

Covers full CRUD, including the FR-008 rejection test (`update` with a changed
`origin_conversation_id` must not change the persisted value), and the FR-007 rejection test
(deleting a `PipelineStage` with existing Opportunities must fail).

## 8. Cross-account guard (FR-004)

Verified via a model spec: creating an `Opportunity` with a `pipeline_stage` from a different
account must raise a validation error.

See [contracts/opportunities-api.md](./contracts/opportunities-api.md) for the full endpoint
contract and [data-model.md](./data-model.md) for field-level detail.
