# Phase 0 Research: Scout V2 Identity and Style Settings

All findings below were verified against the working tree or in the running `rails` container
(`docker compose exec rails bundle exec rails runner …`) on 2026-09-27. No `NEEDS CLARIFICATION`
remains in the plan's Technical Context.

## 1. How the enum currently casts API values (why the check must sit at the request boundary)

**Finding** (in-container probe, Rails 7.2.3.1, `Scout#tone=`):

| Value assigned | Result today |
|---|---|
| `"friendly"` | `"friendly"` |
| `1` (Integer, what a JSON body `{"tone": 1}` produces) | **silently `"neutral"`** |
| `"1"` (String, what a form-encoded body produces) | `ArgumentError: '1' is not a valid tone` → unhandled 500 |
| `"bogus"`, `99` | `ArgumentError` → unhandled 500 |
| `nil`, `""` | `nil` → `ActiveRecord::NotNullViolation` on save → unhandled 500 |

`Scout.tones` / `Scout.response_lengths` are `HashWithIndifferentAccess` with string keys;
`key?(1)`, `key?("1")` and `key?(nil)` are all `false`, `key?("friendly")` is `true`.

**Decision**: Validate `tone` and `response_length` in `Api::V1::Accounts::ScoutsController`
with a `before_action` limited to `create`/`update`, running after `check_authorization` and
`set_scout`. A key present in the permitted params is accepted only when
`Scout.tones.key?(value)` (resp. `Scout.response_lengths.key?(value)`) is true — this admits only
the documented names as strings and rejects `1`, `"1"`, `nil`, `""` and any unknown name. On
rejection it renders the controller's existing error shape (`{ error: "<messages joined by ', '>" }`,
`422`) and the action body never runs, so neither `@scout.update`/`save` nor `sync_attributes`
executes (FR-012). Keys absent from the request are not checked (partial updates keep the
current value).

The message is produced through `ActiveModel::Errors.new(Scout.new)` + `errors.add(attr, :inclusion)`
+ `full_messages`, so it goes through Rails' standard lookup chain
(`activerecord.errors.models.scout.attributes.<attr>.inclusion` → … → `errors.messages.inclusion`)
and `errors.format`, under the locale `switch_locale_using_account_locale` already sets for every
`Api::V1::Accounts::BaseController` request (user `ui_settings.locale`, then account locale).

**Rationale**: FR-010 requires the check before the value reaches the record; the integer case
cannot be caught anywhere later because the cast has already turned it into a valid name.
`AGENTS.md`: "Validate request parameters at the controller or request boundary, reusing existing
errors so invalid input returns 422".

**Alternatives considered**:
- *`enum …, validate: true` on the model (brief §5)* — rejected. It converts `"bogus"`/`"1"` into
  a validation error, but `1` still casts silently to `neutral` before validation runs, so it does
  not satisfy FR-010 on its own; adding it alongside the boundary check is a duplicated guard on the
  same path (`AGENTS.md`: "Do not repeat backup guards"). Console writes of an invalid name keep
  raising `ArgumentError`, which is the loud failure `AGENTS.md` prefers for a setup bug.
- *Override `tone=` on the model to reject integers* — rejected: changes behavior for every
  internal caller and specs that legitimately assign symbols; the requirement is about API input.
- *Hand-built message string* (`"#{Scout.human_attribute_name(attr)} #{I18n.t(...)}"`) — rejected:
  re-implements `errors.format` and the lookup chain `ActiveModel::Errors` already provides.

## 2. Translated error messages in pt_BR

**Finding**: `rails-i18n` is in the `Gemfile`, but the app locale is `pt_BR` (underscore) while
`rails-i18n` ships `pt-BR`; in-container, `I18n.with_locale(:pt_BR) { errors.full_messages }`
returns `"Tone Translation missing … pt_BR.errors.messages.inclusion"` and the same for
`too_long`. In `en` the Rails defaults resolve (`"Tone is not included in the list"`,
`"… is too long (maximum is 500 characters)"`). `Scout.human_attribute_name(:response_length)` is
`"Response length"` in `en` with no pt_BR counterpart.

**Decision**: Add, in both `config/locales/en.yml` and `config/locales/pt_BR.yml`, under the
existing trailing `activerecord:` block (which already carries the `scout_tool` precedent):
- `activerecord.attributes.scout.{role,scope,tone,response_length}` (pt_BR: Papel, Escopo, Tom,
  Tamanho da resposta);
- `activerecord.errors.models.scout.attributes.{tone,response_length}.inclusion` — naming the
  accepted values, mirroring `scout_tool.attributes.auth_type.inclusion`;
- `activerecord.errors.models.scout.attributes.{role,scope}.too_long` — with `%{count}`.

**Rationale**: FR-013/SC-006 require translated rejections in both languages; model-scoped keys are
the narrowest place and follow the existing `scout_tool` pattern in the same files. Both files are
already on the `bin/sync-custom-module-hooks` out-of-scope list, so no MANIFEST change.

**Alternatives considered**: adding generic `pt_BR.errors.messages.inclusion/too_long` — rejected:
changes wording for every model in the app, outside this feature's scope.

## 3. Role/Scope normalization and length limit

**Decision**: On `Scout`:
- `normalizes :role, :scope, with: ->(value) { value.strip.presence }` — Rails 7.2 native; runs on
  every attribute assignment (API, screen, console, `update!`), skips `nil` by default. `String#strip`
  removes leading/trailing ASCII whitespace, `\t`, `\n`, `\r`, `\v`, `\f` and `\0`; internal
  characters (including internal line breaks) are untouched; a whitespace/line-break-only value
  becomes `nil` (FR-001, clarification 5).
- `validates :role, :scope, length: { maximum: 500 }` — runs on the already-normalized value, so
  surrounding whitespace never counts and a 500-char core padded with spaces/newlines is accepted
  (US3 scenario 5). `nil` passes (optional).

The controller adds nothing for Role/Scope: a too-long value makes `@scout.update`/`save` return
`false`, which already renders `422` with `errors.full_messages` and skips `sync_attributes`
(FR-012) — the same path `follow_up_delays_hours` uses today.

**Rationale**: Clarification 5 mandates a single record-level normalization so every write path
behaves the same (and Brief 10's preflight can treat `nil` as empty). Length is a record invariant,
not a request-shape rule, so it belongs with the normalization.

**Alternatives considered**: `before_validation` strip callback — rejected, `normalizes` is the
native construct and also applies to `where(role: …)` lookups; client-side trimming — rejected,
would leave console/API paths unnormalized.

**Character counting note**: Ruby `String#length` counts code points; the textarea's `maxlength`
and the counter count UTF-16 code units. For astral characters (emoji) the screen is stricter than
the server, never looser, so the screen can never produce a server-side `too_long`.

## 4. Column names `role` and `scope` are safe on an ActiveRecord model

**Finding** (in-container): `Scout.dangerous_attribute_method?(:scope)` → `false`,
`(:role)` → `false`; `ActiveRecord::Base.method_defined?(:scope|:role)` → `false`. `scope` is only a
*class* method (`ActiveRecord::Scoping::Named`), which a column does not shadow.

**Decision**: Use the column names `role` and `scope` as the brief and spec name them. Types:
`text`, nullable, no default (consistent with `persona`/`greeting`; the 500 limit is enforced by
the model, not the column type).

## 5. Identity section composition

**Finding**: `Custom::ScoutV2::Instructions::IdentityBuilder#call` today emits exactly:

```text
[Identity]
Você é {scout.name}, um assistente inteligente de qualificação comercial e vendas da empresa {account.name}.
Seu objetivo é qualificar leads, tirar dúvidas sobre produtos e serviços e auxiliar no processo comercial.
Você deve responder apenas sobre os produtos, serviços, catálogo e informações fornecidas neste contexto ou acessíveis através das ferramentas disponíveis.
```

`Instructions::Builder` joins sections with `"\n\n"`; `TurnRunner#build_instructions` calls
`Instructions::Builder.call(scout: @scout)` on every turn with a freshly loaded scout; nothing under
`custom/app/services/custom/scout_v2` caches instructions (`grep Rails.cache|memoize` → none), so a
saved value is visible on the next turn (FR-019).

**Decision**: The section is `"[Identity]"` followed by three statement slots, joined with `"\n"`
(the separator the Default Identity already uses between statements):

| Slot | Role empty | Role filled |
|---|---|---|
| 1 intro | default intro (with qualifier) | `Você é {scout.name}, assistente da empresa {account.name}.` |
| 2 purpose | default purpose statement | `scout.role` as stored |

| Slot | Scope empty | Scope filled |
|---|---|---|
| 3 scope | default scope statement | `scout.scope` as stored |

Both empty ⇒ byte-identical to today (FR-005, SC-003). Stored values are inserted verbatim (no
`squish`, no escaping) — internal line breaks reach the model as typed (FR-004a). Exact text is
pinned in [contracts/identity_section.md](./contracts/identity_section.md).

**Rationale**: `"\n"` keeps SC-003 trivially true (no new separator appears in the empty case) and
keeps each custom value on its own line(s) at its replaced statement's position.

**Alternatives considered**: blank line (`"\n\n"`) around custom blocks — rejected: `"\n\n"` is the
inter-section separator the Builder and its specs split on, so it would make a single Identity
section look like several; and it would change nothing semantically for the model.

**Accepted risk**: an administrator can type a line such as `[Safety]` inside Role/Scope. This is
account-admin-authored content of the same trust level as Persona in V1 (which is also injected
verbatim); the spec requires "stored value as-is, no further treatment". Not mitigated.

## 6. Persona isolation and legacy (V1) invariance

**Finding**: V2's only scout-derived inputs to Instructions are `IdentityBuilder` (`name`,
`account.name`) and `CommunicationBuilder` (`tone`, `response_length`, `greeting`); neither reads
`persona`/`system_prompt`. V1's `Custom::Scout::SystemPromptsService#custom_instructions_section`
reads only `@scout.system_prompt` (alias of `persona`) and V1 never reads `tone`,
`response_length`, `greeting`.

**Decision**: No change to V1 files. FR-006/FR-007 are pinned by tests, not code:
- V2: a Persona marker is absent from `Instructions::Builder.call` output (every section), with
  Role/Scope both empty and both filled.
- V1: under `freeze_time` (its prompt embeds the current time), `SystemPromptsService.build` output is
  identical before and after setting Role, Scope, Tone, Response length and Greeting on the scout,
  and still contains the Persona inside `<account_custom_instructions>`.

## 7. API serialization

**Finding**: `show`/`create`/`update`/`index` render `@scout.as_json(include_associations)`, which
serializes **all** columns; enum attributes serialize by name (`"tone": "friendly"`).
`wrap_parameters :scout, include: Scout.column_names + …` picks up new columns automatically, so an
unwrapped JSON body (what `ScoutAPI.update` sends) is wrapped into `params[:scout]` including
`role`/`scope`.

**Decision**: Only `scout_params`' `allowed` list changes (add `role scope tone response_length
greeting`). Output needs no change for FR-009; Role/Scope come back as stored (trimmed or `null`).

## 8. Settings screen building blocks

**Findings**:
- `components-next/textarea/TextArea.vue`: with `show-character-count` it sets the native
  `maxlength` to `maxLength` and renders `{{ characterCount }} / {{ maxLength }}` — exactly the
  "123 / 500" contract, typing stops at the limit (clarification 3). Persona already uses this
  component (`:max-length="3000"`, counter off).
- `components-next/select/Select.vue`: native `<select>` with `options: [{ value, label }]` and
  `v-model`; already used by `ScoutToolModal.vue`/`ScoutFunnelTab.vue` with
  `class="!w-full [&>select]:w-full"`.
- `ScoutDetail.vue` loads the scout through `ScoutAPI.show` and refetches on `@updated`, so values
  shown after save/reload are the stored ones (normalized Role/Scope).
- `ScoutAPI.update(id, payload)` (inherited `ApiClient`) sends a JSON PATCH; tone/response_length
  travel as the strings bound to the `<select>`.
- Vitest: `vitest.setup.js` installs an empty i18n; `vitest.i18n.js#withFullI18n(locale)` loads real
  messages — used by existing `components-next/scout/overview/*.spec.js`.

**Decision**: In `ScoutGeneralSettings.vue`, add a section (after Persona, before
debounce/quota) with a section title/description and the five fields; tone/response-length option
lists are module-level constants (`TONE_OPTIONS`, `RESPONSE_LENGTH_OPTIONS`, value arrays mapped to
translated labels via `computed`). Role/Scope/Greeting refs default to `''` when the API value is
`null` (TextArea/Input require strings); Tone/Response length refs take the API value directly
(always non-null). All five are included in the existing save payload; Role/Scope are sent as
typed — the model owns their normalization. An empty Greeting is sent as `null`, so saving the
screen keeps a never-filled Greeting `null` instead of turning it into `""` (the API returns
`null` for empty Role/Scope too); whitespace is still absorbed by Greeting's existing semantics
(blank ⇒ generic directive, `squish` at render). The section is rendered
unconditionally (FR-014) — no feature-flag read. UI contract in
[contracts/general_settings_ui.md](./contracts/general_settings_ui.md).

**Alternatives considered**: `ComboBox`/`SelectMenu` — rejected; the Scout tabs standardize on
`Select.vue` for closed lists. A separate tab — rejected; the spec places the fields on the general
settings screen, saved "together with the other general settings".

## 9. Upstream-sync and Enterprise impact

**Findings**:
- `grep -rln '\bScout\b' enterprise/` → no matches; no Enterprise overlay to mirror.
- `bin/sync-custom-module-hooks` already excludes every file this feature touches from `--audit`:
  `custom/`, `db/migrate/2126…`, `db/schema.rb`, `app/javascript/dashboard/components-next/Scout/`,
  `app/javascript/dashboard/i18n/locale/{en,pt_BR}/scout.json`, `config/locales/{en,pt_BR}.yml`,
  `*_spec.rb`, `*.spec.js`.

**Decision**: No MANIFEST entry and no exclusion-list change; no direct upstream/Enterprise edit.

## 10. Migration

**Decision**: `db/migrate/21260927000000_add_role_and_scope_to_ichatr_scouts.rb`, class
`AddRoleAndScopeToIchatrScouts < ActiveRecord::Migration[7.0]`, `change` with two
`add_column :ichatr_scouts, …, :text` — same naming (`2126…` prefix) and shape as
`21260925000000_add_communication_style_to_ichatr_scouts.rb`. No data migration (spec Assumptions:
existing scouts start with empty Role/Scope; Persona is not copied). Run for development and test;
confirm the regenerated `db/schema.rb` diff is only the two columns (AGENTS.md dev-DB contamination
rule; `spec/config/schema_spec.rb` guards n8n leaks).
