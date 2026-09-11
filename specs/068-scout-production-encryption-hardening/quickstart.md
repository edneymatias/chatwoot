# Quickstart: Scout Production Encryption Hardening

Validates that `ActiveRecord::Encryption` is actually configured and enforced for `Scout`/
`ScoutTool` sensitive fields in the real production Swarm deployment (User Story 1 & 2). See
[data-model.md](data-model.md) for the (unchanged) entities and [research.md](research.md) for the
rationale behind each step.

## Prerequisites

- Access to run commands against the production Docker Swarm stack (`docker exec` into a running
  `rails` service task, or an equivalent operator shell).
- The `docker-compose.production.yaml` template in this repo, updated per this feature, as the
  basis for the operator's external Swarm stack file.

## 1. Generate the encryption keys (once)

```bash
docker compose exec rails bin/rails db:encryption:init
```

Copy the three generated values (`primary_key`, `deterministic_key`, `key_derivation_salt`).

## 2. Deliver the keys to the production Swarm stack

Choose either mechanism (operator's choice, per the feature's Clarifications):

- **Explicit `environment:` entries**: fill in the blank
  `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` / `_DETERMINISTIC_KEY` / `_KEY_DERIVATION_SALT` entries
  added to the `rails` and `sidekiq` services in `docker-compose.production.yaml`.
- **Docker Swarm secrets**: `docker secret create` the three values and reference them under
  `secrets:` in the stack file instead of the `environment:` placeholders.

Redeploy: `docker stack deploy -c docker-compose.production.yaml <stack-name>`.

## 3. Verify encryption is recognized as configured (FR-002)

```bash
docker exec <rails-container-id> bin/rails runner "puts Chatwoot.encryption_configured?"
```

**Expected**: `true`.

## 4. Verify round-trip encryption for a Scout (FR-003, User Story 1 Scenario 2)

```bash
docker exec <rails-container-id> bin/rails runner '
  account = Account.first
  scout = Scout.create!(account: account, name: "encryption-smoke-test", provider: "gemini",
                         model_name: "gemini-2.0-flash", api_key_override: "smoke-test-value")
  raw = scout.reload.read_attribute_before_type_cast(:api_key_override).to_s
  puts "raw stored value looks encrypted: #{!raw.include?("smoke-test-value")}"
  puts "decrypted value matches: #{scout.api_key_override == "smoke-test-value"}"
  scout.destroy!
'
```

**Expected**: both lines print `true`; the record is deleted afterward.

## 5. Verify the fail-closed guard when encryption is NOT configured (FR-004/FR-005, User Story 2)

Confirmed by existing automated coverage — no manual production step needed:

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/models/scout_spec.rb custom/spec/models/scout_tool_spec.rb \
  -e "fails closed when encryption keys are not configured"
```

**Expected**: both examples pass, proving `Scout`/`ScoutTool` creation with a populated
`api_key_override`/`auth_headers` raises `ActiveRecord::Encryption::Errors::Configuration` when
keys are absent (see research.md §1).

## 6. Verify non-production environments remain unaffected (User Story 3)

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/models/scout_spec.rb custom/spec/models/scout_tool_spec.rb
```

**Expected**: full suite passes, including the "`encrypts ... unconditionally`" examples that
create records with sensitive fields populated outside production.
