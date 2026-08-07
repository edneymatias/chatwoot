# Quickstart Validation Guide: Table Prefix Rename

This guide documents the procedures for verifying the successful execution of the database rename and namespace policy.

## 1. Verify Clean Codebase

Ensure that the old `matias` prefix has been completely eliminated from application code, tests, and database migrations.

```bash
# Must return zero hits (excluding docs/ directory)
grep -R -i "matias" app/ config/ db/ lib/ spec/ packages/
```

## 2. Rebuild the Database

The local development database must be dropped, created, and re-migrated to ensure the new `ichatr_` migrations execute properly.

```bash
# Execute within the rails container
docker compose exec rails bundle exec rails db:drop db:create db:migrate
```

*Expected Outcome*: The command executes successfully without throwing any `ActiveRecord::StatementInvalid` or migration syntax errors.

## 3. Verify Model Annotations

Regenerate the schema annotations for the models. This verifies that ActiveRecord correctly resolves the new `ichatr_` table names and columns.

```bash
docker compose exec rails bundle exec annotaterb models
```

*Expected Outcome*: The schema header blocks in the 7 custom models should be updated to reflect `ichatr_` table definitions.

## 4. Run Test Suites

Verify functional parity by running the automated suites against the rebuilt database.

```bash
# Ruby backend tests (must run with appropriate env flags)
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec

# Vue frontend tests
docker compose exec vite pnpm test
```

*Expected Outcome*: Both test suites execute completely green with 0 failures.

## 5. Verify the Migration Generator

Validate the new `bin/ichatr-migration` wrapper script.

```bash
# Run the custom generator
bin/ichatr-migration AddTestFieldToIchatrOpportunities

# Check the generated file inside the rails container
docker compose exec rails ls -l db/migrate | grep add_test_field
```

*Expected Outcome*: A migration file is successfully generated in `db/migrate/` and its leading timestamp correctly starts with a year offset +100 years into the future (e.g., `2126...` instead of `2026...`).
