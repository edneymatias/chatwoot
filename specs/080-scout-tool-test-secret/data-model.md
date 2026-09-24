# Phase 1 Data Model: Scout Tool "Test" Real-Credential Reconciliation

No schema/migration changes. This feature adds one new instance method to an existing model and
changes how one existing controller action builds its inputs; no new persisted fields, tables, or
associations.

## Entity: `ScoutTool` (`ichatr_scout_tools`, `custom/app/models/scout_tool.rb`)

Existing relevant shape (unchanged):

| Field | Type | Notes |
|---|---|---|
| `account_id` | integer | FK to `Account`; scopes every lookup (FR-005) |
| `auth_type` | string | one of `AUTH_TYPES = %w[none bearer basic api_key]` |
| `auth_headers` | encrypted text (`encrypts :auth_headers`) | JSON-encoded credential hash; decrypted via `auth_headers`/`parsed_auth_headers` |

Existing behavior (unchanged, reused as-is):

- `MASKED_SECRET = '••••••••'` — the placeholder every read response substitutes for a real
  secret value (`masked_auth_headers`).
- `secret_blank_or_masked?(val)` — `val == MASKED_SECRET || val.blank?`; the existing rule for
  "this submitted value means: keep what's saved."
- `merge_preserved_secrets(incoming, existing)` / `merge_bearer_secret` / `merge_basic_secrets` /
  `merge_api_key_secrets` — per-`auth_type` merge of a submitted credential hash against the
  saved one, substituting the saved secret wherever `secret_blank_or_masked?` is true.

### New method: `ScoutTool#auth_headers_for_test(incoming_credentials)`

- **Visibility**: public (added above the `private` keyword, alongside `apply_credentials_update`
  and `format_response`).
- **Input**: `incoming_credentials` — a Hash-like value (raw or `ActionController::Parameters`),
  the `auth_headers` submitted with a "Test" request; may be `nil`/blank.
- **Output**: a plain `Hash` (string keys) — the credential hash to hand to
  `HttpRequestExecutor`, with any blank/masked secret fields substituted by the receiver's own
  saved, decrypted `parsed_auth_headers`.
- **Side effects**: none. Does not assign `auth_headers=`, does not call `save`/`save!`. Pure
  function of `self` (existing saved state) + the argument.
- **State transitions**: none — this is a read-only reconciliation, never a persistence path.
- **Validation rules**: none new. Inherits the existing implicit rule that only fields recognized
  by the tool's own `auth_type` are merged (mirrors `merge_preserved_secrets`).

Pseudocode (mirrors `apply_credentials_update`, returns instead of assigning):

```ruby
def auth_headers_for_test(incoming_credentials)
  normalized = incoming_credentials.present? ? normalize_incoming_hash(incoming_credentials) : {}
  normalized = {} unless normalized.is_a?(Hash)
  merge_preserved_secrets(normalized, parsed_auth_headers)
end
```

## Controller collaborator: `Api::V1::Accounts::ScoutToolsController#test`

Not a persisted entity, but its inputs change:

| Param (via `test_params`) | Before | After |
|---|---|---|
| `id` | not read | optional; read from `src[:id]` (same `src` the other test params come from) |
| `auth_headers` used for `HttpRequestExecutor` | always the literal submitted value | if `id` resolves to a real tool scoped to `Current.account`, the value returned by `tool.auth_headers_for_test(submitted_auth_headers)`; otherwise the literal submitted value (unchanged, current behavior) |

Tool resolution: `Current.account.scout_tools.find_by(id: tp[:id])` — `nil` for absent, mistyped,
deleted, or cross-account ids, which is treated identically to "no id submitted" (Decision 3 in
`research.md`; FR-008).

## Frontend collaborator: `ScoutToolModal.vue`

`testPayload` (built in `handleTest`) gains one conditional key:

- `id: props.tool.id` — included only when `isEditing.value` is `true` (i.e. `props.tool` is
  present); omitted entirely for a brand-new, unsaved tool. No other field of `testPayload`
  changes shape.
