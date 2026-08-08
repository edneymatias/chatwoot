# Quickstart & Validation Guide

## Prerequisites
- Docker Compose environment running (`docker compose up -d`)

## Validation Steps

### 1. Verify RuboCop (Complexity metrics pass)
Run the following command to ensure the refactored files pass standard RuboCop metrics:
```bash
docker compose exec rails bundle exec rubocop \
  custom/app/models/opportunity.rb \
  custom/app/services/reports/opportunity_funnel_builder.rb \
  lib/seeders/account_seeder.rb \
  spec/bin/sync_custom_module_hooks_spec.rb \
  custom/app/services/custom/automation_rules/action_service.rb
```
**Expected Outcome**: No offenses detected (or only offenses completely unrelated to AbcSize, MethodLength, or CyclomaticComplexity).

### 2. Verify Specs
Run the test suite to ensure the refactoring did not break behavior:
```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  spec/custom/models/opportunity_spec.rb \
  spec/custom/services/reports/opportunity_funnel_builder_spec.rb \
  spec/lib/seeders/account_seeder_spec.rb \
  spec/bin/sync_custom_module_hooks_spec.rb \
  spec/custom/services/custom/automation_rules/action_service_spec.rb
```
**Expected Outcome**: All tests pass.

### 3. Verify .rubocop_todo.yml
Inspect `.rubocop_todo.yml`.
**Expected Outcome**: The file no longer contains `Exclude` entries for the 6 files above under complexity rules, and `Metrics/CyclomaticComplexity` / `Metrics/PerceivedComplexity` are removed entirely.

### 4. Verify .rubocop.yml
Inspect `.rubocop.yml`.
**Expected Outcome**: `Metrics/CyclomaticComplexity` and `Metrics/PerceivedComplexity` both have `Max: 11` defined permanently with an explanatory comment.
