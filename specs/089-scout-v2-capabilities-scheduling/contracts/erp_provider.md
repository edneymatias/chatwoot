# Contract: ERP provider (Younus) and hook settings

Covers FR-007, FR-009, FR-010, FR-012, FR-015, FR-016, FR-026. The provider is
`Erp::Younus::Adapter`; the HTTP layer is `Erp::Younus::Client`. Existing methods
(`find_by_id`, `search_by_phone`, `test_connection`, `fetch_data`, `phone_from`, `external_id_from`)
and `Erp::AdapterFactory` are unchanged; the only edit to `Erp::BaseAdapter` is making `normalize_phone_digits` public (no behavior change).

## 1. Satisfaction (`Adapter.capability_settings`)

```ruby
def self.capability_settings
  {
    'scheduling'        => %w[token id_empresa id_agenda id_servico id_usuario id_convenio],
    'customer_registry' => %w[token id_empresa id_usuario id_convenio nr_convenio id_origem_pessoa]
  }.freeze
end
```

`Capabilities::Registry.resolve(name, account:)` returns a satisfied `Resolution` iff **all** hold:
an enabled hook with app `category: erp` exists (`account.hooks.enabled`), `hook.feature_allowed?`,
`PROVIDERS[hook.app_id]` exists, `capability_settings` has `name`, and every listed key is a non-blank
value in `hook.settings` and every `id_*` key (`id_empresa` included) is digits only (`/\A\d+\z/`); otherwise
unsatisfied, so the client's `Integer()` cannot raise. The two capabilities are evaluated independently (a hook with only the
customer-registry identifiers satisfies `customer_registry` alone).

`Registry.PROVIDERS = { 'younus' => Erp::Younus::Adapter }.freeze`.

Never raises for: no hook, disabled hook, flag off, vendor without a mapping, blank/missing key.

## 2. Provider methods (called by the capability classes; explicit arguments only)

None of these take an identifier, the token or a phone from the model. The phone argument is the
contact's phone already normalized by the capability class (`provider.normalize_phone_digits`, made public by this feature).

| Adapter method | Client method | Returns (already contract-shaped) |
|---|---|---|
| `find_person(phone:)` | `find_person(phone)` | `{ status: :found\|:ambiguous\|:not_found, person: { id:, name: } \| nil }` |
| `create_person(name:, phone:)` | `create_person(name, phone)` | `{ id: String\|nil, name: String }` |
| `list_free_slots(date:)` | `free_slots(date)` | `Array<{ slot_id:, starts_at: }>` (start ascending) |
| `create_appointment(person_id:, person_name:, starts_at:, notes:)` | `create_appointment(...)` | `{ appointment_id: String\|nil, starts_at: String }` |

The adapter owns vendor→contract normalization (`cd_pessoa`/`idPessoa` → id via the existing
`external_id_from`, name from `nm_pessoa`/`nmPessoa`, slot start text → ISO 8601 with the fixed `-03:00` offset (spec Assumption),
appointment reference from the answer). What the vendor omits becomes `nil` and shows up as a
deviation in the capability layer; nothing here raises on an unexpected shape (FR-004).

Naming: the adapter's `person_name` is what the client receives as `title:` (the request's `nmTitulo`,
≤ 100 chars, see the client table below); the model never supplies it (research §6).

### Operation identifier keys hook (`Adapter#operation_identifier_keys(operation_name)`)

`Erp::BaseAdapter#operation_identifier_keys(_operation_name)` defaults to `[]`.
`Erp::Younus::Adapter#operation_identifier_keys(operation_name)` returns the exact identifier keys injected into the ERP request for that operation (`find_by_phone` → `%w[id_empresa]`; `create` → `%w[id_empresa id_usuario id_convenio nr_convenio id_origem_pessoa]`; `list_slots` → `%w[id_empresa id_agenda id_servico]`; `book` → `%w[id_empresa id_agenda id_servico id_usuario id_convenio]`). Used by `OperationTool` to record in the trace only the identifiers actually sent for each call.
## 3. Client requests (`Erp::Younus::Client.new(token:, id_empresa:, settings: {})`)

`settings:` is the hook's `settings` hash restricted by the adapter to the seven identifier keys
(the token stays its own kwarg). Base URI, `token` header, `Content-Type: application/json` and
`default_timeout 5` are the existing ones.

| Client method | HTTP | Path | Query / JSON body |
|---|---|---|---|
| `find_person(phone)` | GET | `/webhook/pesquisar-pessoa` | `idEmpresa`, `nrTelcelpessoa=<phone>` |
| `create_person(name, phone)` | POST | `/webhook/incluir-cliente` | `nmPessoa=<name>`, `idEmpresa`, `idUsuario`, `idConvenio`, `nrConvenio`, `idOrigempessoa`, `nrTelcelpessoa=<phone>` |
| `free_slots(date)` | GET | `/webhook/horarios-livres` | `data=<YYYY-MM-DD>`, `idAgenda`, `idEmpresa`, `idServico` |
| `create_appointment(person_id:, title:, starts_at:, notes:)` | POST | `/webhook/incluir-agendamento` | `idAgenda`, `idPessoa`, `nmTitulo` (≤ 100 chars), `idEmpresa`, `idServico`, `idUsuario`, `idConvenio`, `dtIniAgenda` (`YYYY-MM-DDTHH:mm:ss-03:00`), `observacoes` (`"Agendado por Scout: <notes>"`) |

Numeric identifiers are sent as integers (`Integer(setting)`), `nrConvenio` as a string; `idPessoa`
as an integer. The key set above is exactly the key set of the four `ScoutTool` parameter schemas
(verified against the dev database 2026-09-30); a WebMock `with(query:)`/`with(body:)` example per
method asserts every identifier equals the configured value and (mutant) none is derived from an
argument.

### Error mapping (unchanged behavior extended to the new methods; FR-015)

| Condition | Raised |
|---|---|
| HTTP 401/403 | `Erp::AuthenticationError` |
| 5xx, other non-200 | `Erp::ApiError` |
| timeout / socket / refused | `Erp::ApiError('Connection timed out' \| 'Network error')` |
| unparseable body | `Erp::ApiError('Malformed response from ERP')` |
| POST answered 200 with `sucesso: false` | `Erp::ApiError(<mensagem>)` — a declined write is never success |
| GET `/webhook/horarios-livres` answered 200 with `sucesso: false` | `Erp::ApiError(<mensagem>)` — failure to list slots is an ERP error |
| GET person lookup answered 200 with `sucesso: false` or empty `dados` | not an error: `not_found` / `[]` |

No retries anywhere. `OperationTool` rescues `Erp::Error` only.

> Response envelopes of the three new endpoints are **unverified** at plan time (research §9). Task 0
> captures real bodies into `custom/spec/fixtures/erp/younus/` and this section's parsing rules
> (`dados[].json` envelope assumed, as `/webhook/pessoas`) are confirmed or corrected there before
> the client specs are written.

## 4. Hook settings schema (`config/integration/apps.yml`, `younus`)

```yaml
visible_properties: ['id_empresa', 'token', 'id_usuario', 'id_convenio', 'nr_convenio',
                     'id_origem_pessoa', 'id_agenda', 'id_servico']
settings_json_schema:
  type: object
  properties:
    token:            { type: string }
    id_empresa:       { type: string }
    id_usuario:       { type: string, pattern: '^\d*$' }
    id_convenio:      { type: string, pattern: '^\d*$' }
    nr_convenio:      { type: string }
    id_origem_pessoa: { type: string, pattern: '^\d*$' }
    id_agenda:        { type: string, pattern: '^\d*$' }
    id_servico:       { type: string, pattern: '^\d*$' }
  required: [token, id_empresa]
  additionalProperties: false
settings_form_schema: # existing two items + one text item per new key, no `validation` (optional)
```

(Shown in YAML for readability; the file keeps its existing quoted/JSON-flow style.) Form labels:
`User ID`, `Agreement ID`, `Agreement number`, `Person origin ID`, `Schedule ID`, `Service ID`.
The identical block is the `insert:` of the MANIFEST entry in `bin/sync-custom-module-hooks`.

Compatibility: a hook holding only `token` + `id_empresa` (contact-data card only) stays valid,
`ErpController#data` and `Erp::BaseAdapter#fetch_data` are unaffected, and both capabilities resolve
unsatisfied for it (AS 2.10, AS 2.6).
