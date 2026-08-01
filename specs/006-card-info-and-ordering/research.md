# Research: Card Info Enrichment & Lane Ordering

No `NEEDS CLARIFICATION` items remain from the feature spec or Technical Context —
the source implementation doc
(`docs/kanban/ciclo 2/02-card-info-and-ordering/spec6.md`) already pinned every
technical decision below.

## Decision 1: Represent `created_at` as Unix epoch seconds in `Opportunity#as_json`

- **Decision**: Merge `created_at: created_at.to_i` into `Opportunity#as_json`,
  overriding Rails' default ISO8601 string serialization for that key.
- **Rationale**: The frontend's `dynamicTime`/`shortTimestamp` helpers
  (`app/javascript/shared/helpers/timeHelper.js`) both call `date-fns`'s
  `fromUnixTime`, which expects Unix seconds, not an ISO8601 string. This is the
  same pattern already used for conversations
  (`components-next/Conversation/ConversationCard/ConversationCard.vue` calls
  `shortTimestamp(dynamicTime(timestamp))` on an epoch-seconds field).
- **Alternatives considered**:
  - Leave `created_at` as the default ISO8601 string and add new frontend parsing
    logic to convert it — rejected because it duplicates conversion logic that
    already exists in `timeHelper.js` and diverges from the established
    conversation-card pattern.
  - Add a separate `created_at_ts` key instead of overriding `created_at` —
    rejected as unnecessary API surface; no other consumer of `Opportunity#as_json`
    depends on `created_at` being ISO8601.

## Decision 2: Nested `contact`/`assignee` hashes with `avatar_url` key

- **Decision**: Merge `contact: { id, name, email, avatar_url }` and
  `assignee: { id, name, avatar_url }` (each `nil` when absent) into
  `Opportunity#as_json`, sourcing `avatar_url` from the existing `Avatarable`
  concern (`app/models/concerns/avatarable.rb`, included by `Contact` and `User`).
- **Rationale**: Rails' `as_json` only serializes a model's own columns —
  associations must be manually merged in for the frontend to consume them without
  extra requests. `Avatarable#avatar_url` already returns an absolute URL string
  (or `''` if no avatar), so no new avatar-resolution logic is needed. The key name
  `avatar_url` matches the underlying method name directly, since this is a new
  ad hoc payload shape (not an existing jbuilder partial) with no
  `thumbnail`-key convention to conform to.
- **Alternatives considered**:
  - A dedicated `OpportunitySerializer`/`ActiveModel::Serializer` class — rejected
    per spec Assumptions and Constitution Principle II (smallest change); the
    existing inline `.merge` pattern in `Opportunity#as_json` is sufficient for
    this scope.
  - Reusing the `thumbnail` key from other jbuilder-rendered Contact/Agent
    partials — rejected since those partials aren't used by this
    `as_json`-based endpoint, and reusing an unrelated key name would be
    confusing.

## Decision 3: Enforce lane ordering at the query level

- **Decision**: Add `.order(created_at: :desc)` to the base relation in
  `OpportunitiesController#index`. No changes to the Vuex store.
- **Rationale**: FR-003/FR-004 require newest-first ordering that survives page
  reloads. The `MOVE_CARD_OPTIMISTIC` mutation only reorders the client-held array
  during a drag interaction, held purely in memory; a reload always re-fetches from
  `#index`. Ordering the underlying query is therefore sufficient and is the
  smallest change that satisfies the requirement — no client-side sort or new
  `position`/rank column is needed.
- **Alternatives considered**:
  - Adding a `position` column with manual drag-to-reorder persistence — rejected;
    out of scope per spec Assumptions, which only require stable newest-first
    ordering, not arbitrary manual ordering.
  - Sorting client-side after fetch — rejected as redundant and less reliable
    than sorting in the database query, and it would not survive a fresh page
    load consistently if pagination is added later.

## Note: relative-date i18n

The `dynamicTime`/`shortTimestamp` helpers reused for the creation-date display
(Decision 1) do not wrap their output in an i18n translation function — this is
pre-existing behavior already shipped in `ConversationCard.vue`, not new debt
introduced by this feature. Addressing it fork-wide is out of scope here per
Constitution Principle II (smallest change).
