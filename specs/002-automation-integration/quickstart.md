# Quickstart: Validating the Create Opportunity Automation Action

This phase ships no UI. All validation runs inside the `rails` container per `CLAUDE.md`. Ensure
the stack is up first: `docker compose up -d`.

## 1. Migration applies cleanly and reversibly

```bash
docker compose exec rails bundle exec rails db:migrate
docker compose exec rails bundle exec rails runner "
  puts ActiveRecord::Base.connection.indexes('matias_opportunities').any? { |i| i.columns == ['origin_conversation_id'] && i.unique }
"
# must print true
docker compose exec rails bundle exec rails db:rollback STEP=1
docker compose exec rails bundle exec rails db:migrate
# must succeed without error
```

## 2. Action is registered (FR-001 / contracts/create-opportunity-action.md)

```bash
docker compose exec rails bundle exec rails runner "puts AutomationRule.new.actions_attributes.include?('create_opportunity')"
# must print true
```

## 3. Prepend wiring is minimal (FR-002)

```bash
docker compose exec rails bundle exec rails runner "puts AutomationRules::ActionService.instance_methods(false).include?(:create_opportunity) || AutomationRules::ActionService.private_instance_methods(false).include?(:create_opportunity)"
```

On the host (bind-mounted repo, `git diff` works identically either side):

```bash
git diff app/services/automation_rules/action_service.rb
# must show exactly one added line (the prepend_mod_with call)
```

## 4. End-to-end execution + idempotency (FR-003, FR-004, FR-005; see data-model.md, quickstart Clarifications)

```bash
docker compose exec rails rails console
```
```ruby
account = Account.first
conversation = account.conversations.first
stage = account.pipeline_stages.first || account.pipeline_stages.create!(name: "Leads Recebidos")
rule = account.automation_rules.create!(
  name: "Test", event_name: "conversation_created", conditions: [], account: account,
  actions: [{ action_name: "create_opportunity", action_params: { pipeline_stage_id: stage.id } }]
)

AutomationRules::ActionService.new(rule: rule, account: account, conversation: conversation).perform
Opportunity.where(origin_conversation: conversation).count   # => 1

# re-run to prove idempotency, including the DB-level guarantee from Clarifications
AutomationRules::ActionService.new(rule: rule, account: account, conversation: conversation).perform
Opportunity.where(origin_conversation: conversation).count   # still => 1
```

## 5. I18n label present (FR-008 / contracts/create-opportunity-action.md)

```bash
docker compose exec vite node -e "
  const en = require('./app/javascript/dashboard/i18n/locale/en/automation.json');
  console.log(en.ACTIONS.CREATE_OPPORTUNITY || 'MISSING');
"
# must NOT print MISSING
```

## 6. Automated regression

```bash
docker compose exec rails bundle exec rspec spec/services/automation_rules/action_service_spec.rb
docker compose exec rails bundle exec rspec spec/models/automation_rule_spec.rb
# both green
```
