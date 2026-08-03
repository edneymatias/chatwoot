# Quickstart: Validate Pipeline Stage Reordering

Prerequisites: stack running (`docker compose up -d`), logged in as an account administrator with at least 3 pipeline stages (Super Admin → Accounts → Seed, or create stages manually under Settings → Pipeline Stages).

## 1. Reorder persists (User Story 1 / FR-001, FR-002, SC-001)

1. Go to **Settings → Pipeline Stages**. Note the current order, e.g. `A, B, C, D`.
2. Drag `D` to the top of the list.
3. Expected immediately: list shows `D, A, B, C`.
4. Reload the page.
5. Expected: list still shows `D, A, B, C` — order persisted, and no stage is duplicated or missing.

Backend check (optional):

```
docker compose exec rails bundle exec rails runner "
  pp Account.find(<account_id>).pipeline_stages.order(:position).pluck(:id, :name, :position)
"
```

Expected: `position` values are exactly `1..N` with no duplicates.

## 2. Kanban board reflects the same order (User Story 2 / FR-003, SC-002)

1. After reordering in step 1, open the **Kanban board** (Opportunities).
2. Expected: columns appear left-to-right in the same order as the settings list (`D, A, B, C`), without a manual refresh beyond the normal page load.

## 3. Failed reorder recovers gracefully (User Story 3 / FR-006, SC-004)

1. In DevTools, simulate a network failure or force a `422`/`500` on the next `PATCH .../pipeline_stages/:id` request (e.g. via browser devtools request blocking).
2. Drag a stage to a new position.
3. Expected: an error alert is shown, and the list visually reverts to its previous order — no stage list left in a half-moved state.
4. Remove the simulated failure and confirm a normal drag still works (step 1 still passes).

## 4. No-op drop (Edge case / FR-007)

1. Drag a stage and drop it back into its original position (or drop without an actual index change).
2. Expected (verify via network tab): no `PATCH` request is sent, since the position is unchanged.

## 5. Single-stage account (Edge case)

1. On an account with exactly one pipeline stage, confirm the drag handle has no other stage to reorder against (visually a no-op) and no errors occur.

## Out of scope for this validation

- Real-time propagation to another already-open browser session (out of scope per spec Assumptions) — validating order sync is done via reload/navigation, not live push.
