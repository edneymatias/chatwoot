# Phase 1 Data Model: Opportunity Continuity Detection

No schema changes. No new tables, no new columns on `Opportunity` or any other model (spec's Out of
Scope is explicit about this). This document describes the existing entities the feature reads, and
the one new in-memory value object introduced to carry a decision between the resolver and its two
callers.

## Existing entities involved (unchanged schema)

### Opportunity (`custom/app/models/opportunity.rb`, table `ichatr_opportunities`)

Fields relevant to this feature (all pre-existing):

| Field | Type | Relevance |
|---|---|---|
| `id` | integer | The identifier a declared match refers to, and what candidate lists expose |
| `account_id` | FK | Continuity lookups are always scoped by account |
| `contact_id` | FK | Continuity lookups are always scoped by contact — the anchor for candidate search |
| `status` | enum (`open`/`won`/`lost`) | Only `open` deals are continuity candidates (FR-009) |
| `title` | string | Shown in the structured candidate list exposed to the assistant |
| `pipeline_stage_id` | FK | Shown in the structured candidate list (via `pipeline_stage.name`) |
| `origin_conversation_id` | FK, optional | Still used for the pre-existing origin link; no longer the *only* signal considered |

No new fields. No new validations on this model.

### OpportunityConversation (`custom/app/models/opportunity_conversation.rb`, table
`ichatr_opportunity_conversations`)

Existing many-to-many link between an `Opportunity` and every `Conversation` that has touched it
(created for the origin conversation automatically, and by the Phase 10 in-conversation link
feature for subsequent conversations). Read-only for this feature — the continuity resolver does
not create or modify these rows; a successful "reuse" outcome that leads a caller to attach the
current conversation to the opportunity relies on whatever existing mechanism already creates that
link (unchanged by this feature).

### Contact

Unchanged. Used only as the scoping key (`contact_id`) for the candidate lookup — no new
associations, no new methods required beyond the existing `has_many :opportunities`.

## New value object: `ContinuityDecision`

An in-memory result object returned by `Custom::Opportunities::ContinuityResolverService#call`.
Not persisted — exists only to carry the funnel's outcome, plus enough detail for the caller to act
and for FR-010's traceability requirement (the *why* behind the outcome).

| Attribute | Type | Description |
|---|---|---|
| `outcome` | symbol | One of `:create_new`, `:reuse`, `:ambiguous` |
| `opportunity` | `Opportunity` or `nil` | Present only when `outcome == :reuse` — the matched candidate |
| `candidates` | `Array<Opportunity>` | The full open-deal candidate set considered (used to render the structured system-prompt context, and included for traceability even when empty) |
| `reason` | String | Short, human-readable explanation of why this outcome was reached (e.g. "no open deals for contact", "declared match not in candidate set", "no declared match with 2 open deals present") — this is what gets written into the ambiguity private note and is available for logging |

### State/decision table (the funnel, unchanged from spec FR-001–FR-005/FR-008)

| Candidates for contact | Declared `opportunity_id` | Outcome |
|---|---|---|
| 0 | — (irrelevant) | `:create_new` |
| ≥1 | absent | `:ambiguous` |
| ≥1 | present, matches one candidate | `:reuse` |
| ≥1 | present, does not match any candidate | `:ambiguous` |

The automation-rule call site never supplies a declared `opportunity_id`, so it only ever produces
`:create_new` (0 candidates) or `:ambiguous` (≥1 candidates) — it structurally cannot reach `:reuse`,
which is the intended behavior resolved in `/speckit-clarify`.

## Relationships

```text
Contact 1---* Opportunity (existing, unscoped — unchanged)
Opportunity 1---* OpportunityConversation *---1 Conversation (existing — unchanged)

ContinuityResolverService.new(account:, contact:, declared_opportunity_id: nil).call
  → reads Opportunity.where(account_id:, contact_id:, status: :open)
  → returns ContinuityDecision (in-memory only)
```
