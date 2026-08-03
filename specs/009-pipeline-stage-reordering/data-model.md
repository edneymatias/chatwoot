# Phase 1 Data Model: Pipeline Stage Reordering

No schema/migration changes are needed — the `position` column already exists (`db/migrate/20260730224300_create_matias_pipeline_stages.rb`). This document describes the entity as it participates in the reorder behavior, and the invariant this feature must now enforce.

## Entity: Pipeline Stage (`matias_pipeline_stages` / `PipelineStage`)

| Field | Type | Notes |
|---|---|---|
| `id` | bigint (PK) | unchanged |
| `account_id` | bigint (FK, not null) | reordering is always scoped to this account (FR-004) |
| `name` | string, not null | unchanged |
| `position` | integer, not null | **subject of this feature** — must be unique and sequential (1..N, no gaps) among all stages of the same `account_id` |
| `description`, `requires_deal_value`, etc. | — | unaffected by this feature |
| `created_at` / `updated_at` | timestamps | `updated_at` will bump for every sibling whose `position` shifts during a reorder |

### Invariant (new, enforced by this feature)

For any given `account_id`, the set of `position` values across all of that account's `PipelineStage` rows MUST be `{1, 2, ..., N}` with no duplicates and no gaps, where `N` is the number of stages in the account — at all times after a reorder operation completes (FR-002, SC-003).

- **Enforced by**: transactional renumbering logic in `PipelineStage`/the controller `update` action (see [research.md](./research.md) — "Renumbering algorithm"), not by a DB-level `UNIQUE (account_id, position)` constraint. Adding such a constraint is out of scope for this feature (see Assumptions in spec.md — no new migration is required to satisfy the functional requirements); the transaction + row locking already makes violations practically unreachable through the app's own reorder path.
- **Existing behavior preserved**: `PipelineStage#set_position` (assigns `max(position) + 1` on create) and the `default_scope { order(:position) }` continue to work unchanged — new stages are still appended at the end, and every query already returns stages in position order.

### State transition: Reorder

```
Given: stages S1..SN for account A, ordered by position (1..N)
Trigger: PATCH .../pipeline_stages/:moved_id with { position: target_position }
Effect (single transaction, rows locked for the duration):
  1. Load all of account A's stages, ordered by current position.
  2. Remove the moved stage from its current index.
  3. Reinsert it at (target_position - 1) in the in-memory ordered list.
  4. Walk the resulting list; for every stage whose new index + 1 differs from
     its current position, persist position = index + 1.
  5. Commit. Result: positions are exactly 1..N, reflecting the new order.
Response: the full, freshly-ordered list of account A's stages.
```

No new entities, relationships, or lifecycle states are introduced — this is a persistence-consistency fix to the existing `position` field's write path.
