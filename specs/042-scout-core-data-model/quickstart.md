# Quickstart: Scout Core & Data Model

Validates SC-001 through SC-005 end to end via Rails console/seed only — no UI, no message
pipeline. See [data-model.md](./data-model.md) for full field/association details and
[research.md](./research.md) for the encryption and LLM-client design decisions referenced below.

## Prerequisites

- Stack running: `docker compose up -d`
- Migrations applied: `docker compose exec rails bundle exec rails db:migrate`
- `ActiveRecord::Encryption` configured in `.env` (`ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`,
  `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`, `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`) —
  generate with `docker compose exec rails bin/rails db:encryption:init` if not already set
- A real API key for at least one of `gemini`/`openai`/`anthropic`, for the round-trip check
- An existing `Account` and `Inbox` in the target environment (e.g. from `rails db:seed`)

## 1. Provision a Scout (SC-001)

```
docker compose exec rails bundle exec rails console
```

```ruby
account = Account.first
inbox   = account.inboxes.first

scout = Scout.create!(
  account: account,
  name: "Sales Scout",
  provider: :gemini,           # or :openai / :anthropic
  model_name: "gemini-2.0-flash",
  api_key_override: ENV.fetch("GEMINI_API_KEY")
)

ScoutInbox.create!(scout: scout, inbox: inbox)
```

**Expected**: both records persist; `scout.inboxes` includes `inbox`.

## 2. Confirm inbox uniqueness is enforced (FR-002a)

```ruby
other_scout = Scout.create!(account: account, name: "Support Scout", provider: :openai, model_name: "gpt-4o", api_key_override: "sk-...")
ScoutInbox.create!(scout: other_scout, inbox: inbox)   # same inbox as step 1
```

**Expected**: raises `ActiveRecord::RecordInvalid` (uniqueness violation on `inbox_id`).

## 3. Confirm provider enum rejects invalid values (FR-001a)

```ruby
Scout.new(account: account, name: "Bad Scout", provider: "openrouter", model_name: "x").provider
```

**Expected**: raises `ArgumentError` (`'openrouter' is not a valid provider`) — no record created.

## 4. Prove the LLM tool-calling round-trip (SC-001, User Story 1 Scenario 2)

```ruby
chat = scout.llm_chat   # resolves provider/model/api_key_override into a RubyLLM::Chat instance
response = chat.ask("What's the weather in Rio de Janeiro?", with: ->(city:) { "22C, clear" })
```

**Expected**: a real HTTP round-trip to the configured provider completes and `response` contains
the provider's reply — proving `RubyLLM.context`-based multi-provider resolution (research.md §1)
works without any custom gateway code.

## 5. Confirm credentials are unreadable in the database (SC-002)

```
docker compose exec postgres psql -U postgres -d chatwoot_development -c \
  "SELECT api_key_override FROM ichatr_scouts WHERE id = <scout.id>;"
```

**Expected**: the returned value is ciphertext (base64 blob), not the plaintext key.

## 6. Confirm encryption failure closes safely, not open (SC-003)

Temporarily unset the encryption env vars and restart the `rails` service, then:

```ruby
Scout.create!(account: account, name: "Unsafe", provider: :gemini, model_name: "x", api_key_override: "plaintext-key")
```

**Expected**: raises (e.g. `ActiveRecord::Encryption::Errors::Configuration`) — the record is NOT
persisted with a plaintext key. Restore the encryption env vars afterward.

## 7. Confirm quota_available? (SC-004)

```ruby
Scout.new(responses_quota: -1, responses_consumed: 999_999).quota_available?   # => true
Scout.new(responses_quota: 10, responses_consumed: 9).quota_available?         # => true
Scout.new(responses_quota: 10, responses_consumed: 10).quota_available?        # => false
Scout.new(responses_quota: 0, responses_consumed: 0).quota_available?          # => false
```

## 8. Confirm migrations roll back cleanly (SC-005)

```
docker compose exec rails bundle exec rails db:rollback STEP=4
docker compose exec rails bundle exec rails db:migrate:status
```

**Expected**: all four new migrations (3 `ichatr_scout*` tables + `lost_reason` column) show as
`down`, then re-running `db:migrate` brings them back to `up` with no errors.
