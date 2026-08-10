# Data Model

## Entities

### `Opportunity` (Existing)

- **New Validation Rules**:
  - `origin_conversation_id` becomes immutable once set.
  - Specifically, a validation ensures that if `origin_conversation_id` is changed, the `origin_conversation_id_was` must have been `nil`.

## State Transitions

- **Unlinked Opportunity**: `origin_conversation_id` is `nil`.
- **Linked Opportunity**: `origin_conversation_id` contains a valid conversation ID.
  - *Transition Rule*: Unlinked -> Linked is allowed via `update`. Linked -> Unlinked or Linked -> Linked (different ID) is rejected.
