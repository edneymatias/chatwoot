# Quickstart: Validating Scout V2 Identity and Style Settings

Validation guide only — contracts live in [contracts/](./contracts/), field rules in
[data-model.md](./data-model.md).

## Prerequisites

- Stack up: `docker compose up -d` (services `rails`, `vite`, `postgres`, `redis`).
- A dev account with the `scout` feature, a `ScoutAccountConfig` with an API key, and at least one
  scout (`docker compose exec rails bundle exec rails db:seed` if the dev DB is empty).
- Migration applied in both environments:

```bash
docker compose exec rails bundle exec rails db:migrate
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rails db:migrate
git diff --stat db/schema.rb   # expect only the two ichatr_scouts columns + version bump
```

If the `schema.rb` diff shows anything else (e.g. `n8n` triggers), stop and clean the dev DB per
`AGENTS.md` before continuing.

## 1. Targeted automated checks (Constitution IX — no full suite while iterating)

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/models/scout_spec.rb \
  custom/spec/services/custom/scout_v2/instructions/identity_builder_spec.rb \
  custom/spec/services/custom/scout_v2/instructions/builder_spec.rb \
  custom/spec/services/custom/scout/system_prompts_service_spec.rb \
  custom/spec/controllers/api/v1/accounts/scouts_controller_spec.rb \
  custom/spec/services/custom/scout_v2/turn_runner_spec.rb

docker compose exec vite pnpm vitest run \
  app/javascript/dashboard/components-next/Scout/pageComponents/specs/ScoutGeneralSettings.spec.js

docker compose exec rails bundle exec rubocop custom/app/models/scout.rb \
  custom/app/controllers/api/v1/accounts/scouts_controller.rb \
  custom/app/services/custom/scout_v2/instructions/identity_builder.rb \
  db/migrate/21260927000000_add_role_and_scope_to_ichatr_scouts.rb \
  custom/spec/models/scout_spec.rb \
  custom/spec/services/custom/scout_v2/instructions/identity_builder_spec.rb \
  custom/spec/services/custom/scout_v2/instructions/builder_spec.rb \
  custom/spec/services/custom/scout/system_prompts_service_spec.rb \
  custom/spec/controllers/api/v1/accounts/scouts_controller_spec.rb \
  custom/spec/services/custom/scout_v2/turn_runner_spec.rb
docker compose exec vite pnpm eslint app/javascript/dashboard/components-next/Scout/pageComponents/ScoutGeneralSettings.vue
```

Expected: all green. Each spec file must have been observed failing for the missing behavior before
the implementation landed (Constitution VI/VIII).

## 2. Identity composition from the console (US1)

```bash
docker compose exec rails bundle exec rails runner '
s = Scout.first
s.update!(role: nil, scope: nil, persona: "MARCADOR-PERSONA-XYZ")
puts Custom::ScoutV2::Instructions::IdentityBuilder.call(scout: s)
s.update!(role: "  SDR da clínica, atende adultos em SP.\n", scope: "- não informa preços\n- não agenda urgências")
puts "---"; puts Custom::ScoutV2::Instructions::IdentityBuilder.call(scout: s)
puts "persona leaked? #{Custom::ScoutV2::Instructions::Builder.call(scout: s).include?("MARCADOR-PERSONA-XYZ")}"
p s.reload.role
'
```

Expected:
- First block equals the "Both empty" case in [contracts/identity_section.md](./contracts/identity_section.md).
- Second block equals the "Both filled" case: neutral intro, the Role line, then the two Scope lines
  as a list.
- `persona leaked? false`.
- `s.role` is `"SDR da clínica, atende adultos em SP."` (ends trimmed).

Restore the scout's original Persona afterwards if it was real data.

## 3. API boundary (US3)

Get an admin token: `docker compose exec rails bundle exec rails runner 'puts User.find_by(email: "<admin email>").access_token.token'`.

```bash
TOKEN=...; ACC=<account_id>; ID=<scout_id>; URL="http://localhost:3000/api/v1/accounts/$ACC/scouts/$ID"

# valid write — 200, five fields echoed, role trimmed, whitespace scope → null
curl -s -X PATCH "$URL" -H "api_access_token: $TOKEN" -H 'Content-Type: application/json' \
  -d '{"role":"\n SDR\n- adultos \n","scope":"  \n ","tone":"professional","response_length":"thorough","greeting":"Olá!"}' \
  | jq '{role,scope,tone,response_length,greeting}'

# each of these — 422, translated message, `name` unchanged afterwards
for body in '{"name":"X","tone":1}' '{"name":"X","tone":"1"}' '{"name":"X","tone":"bogus"}' \
            '{"name":"X","response_length":"long"}' "{\"name\":\"X\",\"role\":\"$(printf 'a%.0s' {1..501})\"}"; do
  curl -s -o /dev/stderr -w '%{http_code}\n' -X PATCH "$URL" -H "api_access_token: $TOKEN" \
    -H 'Content-Type: application/json' -d "$body"
done
curl -s "$URL" -H "api_access_token: $TOKEN" | jq .name   # still the original name
```

Repeat one rejected call after setting the admin's UI language to Português (Profile settings) and
confirm the message is in Portuguese (see [contracts/scouts_api.md](./contracts/scouts_api.md) for
exact texts).

## 4. Settings screen (US2)

1. Open `http://localhost:3000` → Scout → Agents → a scout on an account **without** the
   `scout_v2` flag → General tab.
2. Confirm the "new version" section shows Role, Scope, Tone, Response length, Greeting, each with a
   hint mentioning the new version; Greeting's hint advises leaving it blank when the inbox already
   greets. Persona is unchanged.
3. Tone lists 5 options, Response length 3, all translated.
4. Paste > 500 chars into Role: input stops, counter reads `500 / 500`.
5. Change all five, Save, reload the page: values persist (Role/Scope shown trimmed).
6. Switch UI language to Português, reload: every new label/option/hint/placeholder is in Portuguese.
7. Enable `scout_v2` for the account in Super Admin, reopen the tab: same five fields, same way.

## 5. Next V2 reply reflects the saved values (FR-019, SC-002)

With `scout_v2` enabled on the account, send a message from the scout's Playground tab right after
step 4's save. In the turn trace (or `docker compose logs -f rails` instrumentation), the
instructions' `[Identity]` contains the saved Role/Scope per the contract, and `[Communication]`
contains the directive sentences for the saved Tone/Response length and the quoted Greeting — no
console step involved.

## 6. Legacy version untouched (FR-007, SC-004)

Disable `scout_v2`, send a Playground message: V1 answers as before; its prompt still carries the
Persona inside `[Instruções Personalizadas da Conta]` and none of Role/Scope/style text. The
automated guard is the `system_prompts_service_spec.rb` example that compares the V1 prompt before
and after setting the five fields under frozen time.
