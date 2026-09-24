# Phase 1 Data Model: Scout Playbook Loader and Boot Validation

All entities are plain Ruby objects (no ActiveRecord, no migration this phase — see research.md
D8/plan.md Storage). Field names match the frontmatter keys in `design.md` §4.3 verbatim so the
file format is the schema.

## Playbook (`Custom::ScoutV2::Playbook`)

One versioned file (`custom/playbooks/<name>.md`) → one instance. Immutable value object built by
`Loader`, consumed by `Catalog`/`Validator`/(later) the router.

| Field | Type | Required | Default when absent | Source |
|---|---|---|---|---|
| `name` | String matching `\A[a-z][a-z0-9_]*\z` | yes (FR-004) | `nil` — Loader does not default; absence is a boot violation (FR-004) | frontmatter `name` |
| `title` | String | yes (FR-004) | `nil`, same as `name` | frontmatter `title` |
| `priority` | Integer | yes, must be `Integer`, unique across catalog (FR-004, clarification #1) | `nil` — never coerced from string/float (Edge Cases) | frontmatter `priority` |
| `trigger` | String | yes (FR-004) | `nil`, same as `name` | frontmatter `trigger` |
| `when_state` | `Array<[String, String\|nil]>` — each entry normalized to a `[predicate_name, arg]` pair; bare string entries become `[name, nil]`, single-key mappings become `[key, value]` | no | `[]`, never `nil` (FR-003). A non-list value or an entry that is neither a String nor a single-key mapping is recorded in `load_errors`, never dropped silently | frontmatter `when_state` |
| `requires` | `Array<String>` (capability names) | no | `[]`, never `nil` (FR-003) | frontmatter `requires` |
| `needs` | `Array<String>` (knowledge item names) | no | `[]`, never `nil` (FR-003) — **not validated against any catalog this phase** (no FR covers it) | frontmatter `needs` |
| `tools` | `Array<String>` (tool names) | no | `[]`, never `nil` (FR-003) — **not validated against any catalog this phase** (no FR covers it) | frontmatter `tools` |
| `exits` | `Hash<String, Hash<String,String>>` — ending name (same format as `name`) → `{ field_name => type_name_string }` | no | `{}`, never `nil` (FR-003, clarification #2). A non-mapping value is recorded in `load_errors` | frontmatter `exits` |
| `body` | String | no (not in FR-004's required list) | `''` if the closing `---` is immediately followed by nothing | text after the frontmatter's closing `---` delimiter, preserved byte-for-byte (FR-002) |
| `file_path` | String | always set by `Loader` | — | not a frontmatter field; internal bookkeeping so `Validator` error messages can name the offending file (FR-007–011, FR-017) |
| `load_errors` | `Array<String>` | always set by `Loader` (`[]` when the file loaded cleanly) | `[]` | not a frontmatter field; frontmatter the Loader could not use (unparseable YAML, badly shaped `when_state`/`exits`) so the Validator reports it instead of the Loader dropping it |

**Validation rules** (enforced by `Playbook::Validator`, not by `Loader` — see research.md D2):
one violation entry per broken rule; every rule below is independently checked and all violations
across the whole catalog are collected before raising once.

- Every `load_errors` entry → violation.
- `name`, `title`, `trigger` blank → violation.
- `name` present but not a String matching `\A[a-z][a-z0-9_]*\z` → violation; same rule for every
  `exits` key.
- `priority` `nil` or not an `Integer` → violation.
- Two or more playbooks share the same non-nil `priority` → violation naming both/all files.
- Two or more playbook files declare the same non-blank `name` → violation naming both/all files,
  independent of file path (clarification #3).
- Any `when_state` entry's predicate name not `Predicates::Registry.registered?` → violation.
- Any `requires` entry not `Capabilities::Catalog.known?` → violation.
- Any `exit_<name>` token in `body` (captured as `exit_` followed by word characters or hyphens, so
  a token spelled outside the name format is still caught) where `<name>` is not a key of this
  playbook's own `exits` → violation (per-playbook scope — an ending declared in a *different*
  playbook's `exits` does not satisfy this).
- Any `open_playbook(<name>)` token in `body` (captured as everything inside the parentheses, minus
  optional quotes) where `<name>` is not a `name` present anywhere in the loaded catalog → violation.
- **Not** a violation: `exits` empty or absent (clarification #2); `when_state` empty (trigger-only
  activation, Edge Cases); zero playbook files loaded (Edge Cases, Assumptions).

## Playbook Catalog (`Custom::ScoutV2::Playbook::Catalog`)

The full loaded set for one process boot.

| Member | Signature | Behavior |
|---|---|---|
| `playbooks` | `Array<Playbook>` | all loaded playbooks, load order |
| `find_by_name(name)` | `(String) -> Playbook \| nil` | exact-string match on `#name`; `nil` if absent, never raises |
| `ordered_by_priority` | `() -> Array<Playbook>` | sorted by `priority` descending (research.md D10); playbooks with `nil` priority (pre-validation state) sort last |
| `each` / `Enumerable` | — | `Catalog` includes `Enumerable` over `playbooks` so validators/specs can iterate without reaching into `.playbooks` |

An empty directory produces a `Catalog` with `playbooks == []` — a valid, non-error state (Edge
Cases, Assumptions). A missing directory is a deployment bug: `Loader` raises `Errno::ENOENT`.

## Condition Check / Predicate (`Custom::ScoutV2::Predicates::*`)

| Entity | Shape |
|---|---|
| `Predicates::Base` | abstract; `#call(ctx, arg = nil) -> true \| false`, raises `NotImplementedError` if not overridden |
| `Predicates::OpportunityOpen` | `#call(ctx, _arg = nil) = ctx.opportunity&.status.to_s == 'open'` |
| `Predicates::PendingRequiredFields` | `#call(ctx, _arg = nil) = ctx.pending_fields.present?` |
| `Predicates::Registry` | `.registered?(name) -> Boolean`; `.resolve(name) -> Class` (raises `ArgumentError` if unregistered — never returns a silent stand-in, FR-016) |
| `Predicates::Evaluator` | `.call(when_state, ctx) -> Boolean` — logical AND over every `[name, arg]` pair in `when_state`, resolving each via `Registry.resolve`; vacuously `true` for an empty list |

## Declared Capability Catalog (`Custom::ScoutV2::Capabilities::Catalog`)

| Member | Signature | Behavior |
|---|---|---|
| `KNOWN_NAMES` | `Array<String>` (frozen) | `%w[scheduling customer_registry]` (research.md D5) |
| `.known?(name)` | `(String) -> Boolean` | exact-string, case-sensitive membership check (Edge Cases: no normalization) |

Resolving/instantiating a capability adapter is explicitly out of scope (brief 07,
`CapabilityRegistry`) — this entity only answers "is this name declared," per FR-008 and the
spec's Key Entities note.

## Routing Context (`Custom::ScoutV2::RoutingContext`)

Minimal seed (research.md D8) of the eventual full router context (design.md §4.4).

| Field | Type |
|---|---|
| `opportunity` | `Opportunity \| nil` |
| `pending_fields` | `Array<String>` (empty array when nothing pending) |

## Boot Validation Failure (`Custom::ScoutV2::Playbook::Validator::ValidationError`)

`StandardError` subclass, nested inside `Validator` (no separate file — Constitution II). Raised
once per `Validator.call!` invocation with every collected violation.

| Aspect | Behavior |
|---|---|
| Construction | `ValidationError.new(violations)` where `violations` is `Array<String>`, each already formatted as `"<file_path>: <specific broken reference or value>"` |
| `#message` | `violations.join("\n")` — every problem visible in one raised error, matching Assumptions ("collecting every broken reference found in that pass") |
| Callers | `Validator.call!` (raises); boot initializer lets it propagate uncaught (process fails to become ready); RSpec `validator_spec.rb` asserts on `#violations` (file path plus broken reference per entry) |
