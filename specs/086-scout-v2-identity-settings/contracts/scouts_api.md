# Contract: Scout Settings API — Identity and Style Fields

Controller: `Api::V1::Accounts::ScoutsController` (`custom/app/controllers/api/v1/accounts/scouts_controller.rb`).
Auth/permissions unchanged (`check_authorization` → `ScoutPolicy`). Locale for messages: the
existing `switch_locale_using_account_locale` (user `ui_settings.locale`, else account locale).

Endpoints affected:

| Method | Path | Change |
|---|---|---|
| `POST` | `/api/v1/accounts/{account_id}/scouts` | accepts the five fields |
| `PATCH`/`PUT` | `/api/v1/accounts/{account_id}/scouts/{id}` | accepts the five fields |
| `GET` | `/api/v1/accounts/{account_id}/scouts/{id}` and `/scouts` | response carries the five fields (already, via `as_json` of all columns) |

Body may be wrapped (`{ "scout": { … } }`) or unwrapped (JSON body auto-wrapped by
`wrap_parameters`), as for every existing field.

## Request fields (all optional; absent ⇒ unchanged)

| Field | Type | Accepted values | Server treatment |
|---|---|---|---|
| `role` | string \| null | any text | stripped at both ends; blank ⇒ `null`; ≤ 500 chars after stripping |
| `scope` | string \| null | any text | same as `role` |
| `tone` | string | `friendly`, `neutral`, `matter_of_fact`, `professional`, `humorous` | stored as-is |
| `response_length` | string | `concise`, `standard`, `thorough` | stored as-is |
| `greeting` | string \| null | any text | stored as sent (no new rule); the screen sends `null` when empty |

## Response (200 / 201) — additional keys in the scout JSON

```json
{
  "id": 12,
  "name": "Clara",
  "persona": "…legacy text, unchanged…",
  "role": "SDR da clínica, atende pacientes adultos em São Paulo.",
  "scope": "- não informa preços de tratamento\n- não agenda urgências",
  "tone": "professional",
  "response_length": "standard",
  "greeting": "Olá! Aqui é a Clara, da Sorriso Odonto.",
  "...": "all other existing keys unchanged"
}
```

`tone`/`response_length` always returned by name. `role`/`scope` returned as stored (trimmed, or
`null`).

## Rejections (422, nothing persisted)

Error body shape is the controller's existing one: `{ "error": "<full messages joined by ', '>" }`.

| Condition | Checked at | Message (en / pt_BR) |
|---|---|---|
| `tone` present and not a String name in the list (incl. `1`, `"1"`, `null`, `""`, `"bogus"`) | controller `before_action` (before any write) | `Tone is not included in the list of supported tones (friendly, neutral, matter_of_fact, professional, humorous)` / `Tom não está incluído na lista de tons suportados (friendly, neutral, matter_of_fact, professional, humorous)` |
| `response_length` present and not a String name in the list | controller `before_action` | `Response length is not included in the list of supported response lengths (concise, standard, thorough)` / `Tamanho da resposta não está incluído na lista de tamanhos de resposta suportados (concise, standard, thorough)` |
| `role` longer than 500 after stripping | model validation (`update`/`save` returns false) | `Role is too long (maximum is 500 characters)` / `Papel é muito longo (máximo de 500 caracteres)` |
| `scope` longer than 500 after stripping | model validation | `Scope is too long (maximum is 500 characters)` / `Escopo é muito longo (máximo de 500 caracteres)` |

Guarantees (FR-012):
- A boundary rejection halts before `@scout.update`/`save` and before `sync_attributes`; a model
  rejection returns before `sync_attributes`. Either way the scout's columns **and** its
  `required_custom_attribute_definitions` are unchanged, including valid fields sent alongside.
- The boundary check runs on `POST` as well as `PATCH`/`PUT`: a rejected create persists no scout.
- When both `tone` and `response_length` are invalid, both messages are returned. When a boundary
  field is invalid, model-level Role/Scope messages are not evaluated (the record is never touched).
- No input in this table yields a 5xx.

Locale keys backing the messages (both `config/locales/en.yml` and `config/locales/pt_BR.yml`):

```yaml
activerecord:
  attributes:
    scout: { role, scope, tone, response_length }
  errors:
    models:
      scout:
        attributes:
          tone: { inclusion }
          response_length: { inclusion }
          role: { too_long }      # uses %{count}
          scope: { too_long }     # uses %{count}
```

## Examples

```http
PATCH /api/v1/accounts/1/scouts/12
Content-Type: application/json

{ "name": "Novo nome", "tone": 1 }
```
→ `422 { "error": "Tone is not included in the list of supported tones (friendly, neutral, matter_of_fact, professional, humorous)" }`; `name` unchanged.

```http
PATCH /api/v1/accounts/1/scouts/12
Content-Type: application/json

{ "role": "\n  SDR da clínica\n- adultos\n  ", "scope": "   \n " }
```
→ `200`, `"role": "SDR da clínica\n- adultos"`, `"scope": null`.
