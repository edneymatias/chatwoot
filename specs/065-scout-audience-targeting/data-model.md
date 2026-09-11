# Phase 1 Data Model: Scout Audience Targeting

## Overview

This feature adds one new persisted attribute to the existing `Scout` entity; it introduces no new
database tables. `Targeting Condition` is a value shape stored inside that attribute, not a
separate model.

## Scout (existing entity — extended)

| Field | Type | Notes |
|---|---|---|
| `audience` | `jsonb`, array | **New**. Ordered array of Targeting Condition objects (see below). `NOT NULL`, default `[]`. Empty array is the default/unconfigured state — Scout engages every contact (spec FR-003). |

No new validations are required at the `Scout` model level: an empty array is always valid. A
condition with an unrecognized `attribute_key`/`filter_operator` simply evaluates as "no match"
(see Validation rules below) rather than raising — no save-time schema validation is added for this
column (kept out of scope; the UI is the only writer and always emits well-formed conditions).
This differs from Chatwoot's own Enterprise `Captain::AudienceValidator`, which *does* validate
audience shape at save time — deliberately not mirrored here (see research.md) since our matcher
handles unrecognized shapes safely without it, but noted as a residual gap: a genuinely malformed
`audience` value (e.g. hand-edited via direct API access) fails silently to "no match" per
condition rather than being rejected up front.

### New behavior: `Scout#engages?(contact, conversation)`

Not a stored field — a derived boolean method: "would this Scout, given its current `audience`,
engage this specific contact/conversation pair?" Delegates evaluation to the audience-matching
service. Returns `true` unconditionally when `audience` is blank (FR-003).

## Targeting Condition (value object, stored inside `Scout#audience`)

Not an ActiveRecord model — a plain hash shape, one element of the `audience` array.

| Field | Type | Notes |
|---|---|---|
| `attribute_key` | string | Which Contact attribute this condition inspects (e.g. `phone_number`, `email`, `labels`, `country_code`, or a custom attribute's key). Conversation-level keys (e.g. `browser_language`) are deferred — see Attribute source resolution below. |
| `filter_operator` | string | Match operator: `equal_to`, `not_equal_to`, `is_present`, `is_not_present`, `contains`, `does_not_contain`, `starts_with`, `greater_than`, `less_than` — same operator vocabulary already used by Kanban/Contacts filters and automation rules. |
| `values` | array of string | The value(s) to compare against. Most operators use the first value; equality-style operators may compare against any of several. |
| `query_operator` | string, `"and"` \| `"or"` | How this condition combines with the condition immediately before it in the array. Ignored on the first condition (nothing precedes it). |

**Validation rules**: None enforced server-side beyond what the shared frontend condition-row
component already produces. An unrecognized `attribute_key` or `filter_operator` simply fails to
match (falls through to "no match" for that condition) rather than raising. Separately, a
*recognized* operator/attribute pair whose stored value can't be meaningfully compared (e.g. a
`greater_than`/`less_than` numeric or date comparison against a non-numeric/non-date string) is
caught with a narrow, local rescue and also treated as "no match" for that one condition (FR-007) —
evaluation of the remaining conditions in the audience continues normally. There is deliberately
**no** blanket top-level rescue around the whole audience evaluation: a genuine unexpected error
(a bug, not a bad value) is allowed to raise and surface loudly, per this fork's convention of
never silently swallowing misconfigured/broken state (see research.md decision on error handling
and CLAUDE.md's "General Guidelines").

**Relationships**: Belongs conceptually to exactly one `Scout` (embedded, not a foreign-keyed
row). Evaluated against exactly one `Contact` at a time — never against a set/collection, and
never against a `Conversation` in this phase (see Attribute source resolution below).

**State/lifecycle**: Stateless value data; the array is replaced wholesale on every save from the
UI (no per-condition create/update/delete endpoint — the whole `audience` array is written
together, consistent with how the existing Scout `update` action already persists array-typed
fields such as `follow_up_delays_hours`).

## Attribute source resolution (read-only, not new data)

Each `attribute_key` on a Targeting Condition resolves against one of two existing attribute
sources at evaluation time — no new attributes are introduced by this feature, only made
selectable within a Scout's audience:

- **Contact attributes**: `name`, `email`, `phone_number`, `identifier`, `blocked`, and
  additional-attribute-backed fields `country_code`, `city`, `company_name`, plus `labels`.
- **Custom attributes**: any account-defined contact custom attribute, looked up by key.

**Deferred**: Conversation-level attributes (e.g. `browser_language` from
`additional_attributes`) are explicitly out of scope for this phase. `useContactFilterContext()` —
the composable this feature reuses for the condition-building UI — only exposes contact
attributes; there is no conversation-attribute source in that provider today. Adding a
conversation attribute to the selectable list without a UI path to configure it would ship a
backend capability with no way to use it, so it is deferred to a future extension that also adds
the corresponding frontend plumbing. `Scout#engages?` keeps its `conversation:` parameter (needed
by the calling hooks regardless — see below), but the matcher does not yet look at it.

## Entity relationship summary

```text
Scout (existing) ──has── audience: [TargetingCondition, ...]   (jsonb column, embedded)

TargetingCondition ──evaluated against──> Contact (existing)

Scout#engages?(contact, conversation) ──consulted by──> Conversation#determine_conversation_status
                                        ──consulted by──> Message#reopen_resolved_conversation
```
