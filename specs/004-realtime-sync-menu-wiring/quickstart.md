# Quickstart: Realtime Sync & Menu/Route Wiring

Prerequisites: stack is up (`docker compose up -d`); Phase 1-3 backend/frontend already in place;
Kanban feature flag enabled for a test account.

## 1. Verify the realtime broadcast fires (FR-001-003)

```
docker compose exec rails bundle exec rspec spec/models/opportunity_spec.rb
```

Expected: a spec asserting `ActionCableBroadcastJob` receives `perform_later` with
`["account_#{account.id}"]`, `'opportunity_updated'`, and a hash including `id`,
`pipeline_stage_id`, `status`, `contact_id`, `assignee_id`, `updated_at`, `account_id` — see
`contracts/opportunity_updated_event.md` and the testing precedent in `research.md` §8.

## 2. Verify frontend event handling (FR-002/FR-004)

```
docker compose exec vite pnpm test -- actionCable
```

Expected: a spec feeding an `opportunity_updated` payload into the ActionCable helper and
asserting the `opportunities` Vuex module's `cardIdsByStage` and `cardsById` update in place.

## 3. Verify the sync script on a clean baseline (FR-005/FR-009)

```
docker compose exec rails bin/sync-custom-module-hooks --check
```

Expected: exit code `0`, all wiring points (including the 7 already-committed ones — see
`research.md` §6 — plus the 2 new ones this phase adds) reported present.

## 4. Verify apply idempotency (FR-011)

```
docker compose exec rails bin/sync-custom-module-hooks --apply
git diff --stat
docker compose exec rails bin/sync-custom-module-hooks --apply
git diff --stat   # identical — no duplicate insertions
```

## 5. Verify fail-fast behavior (FR-006/FR-012)

```
sed -i "s/'conversation.updated': this.onConversationUpdated,//" app/javascript/dashboard/helper/actionCable.js
docker compose exec rails bin/sync-custom-module-hooks --check
echo $?   # non-zero
git checkout -- app/javascript/dashboard/helper/actionCable.js
```

Expected: stderr names the exact file and missing anchor (see `contracts/sync-script-cli.md`).

## 6. End-to-end manual verification (FR-005-008, User Story 2 & 1)

1. Enable the Kanban feature flag for a test account; log in as a non-admin agent.
2. Confirm a main-navigation entry opens the board at `accounts/:accountId/opportunities`.
3. Log in as an administrator; confirm Settings shows "Pipeline Stages" and a non-admin agent does
   not see it.
4. Open the board in two browser sessions on the same account; drag a card to a new stage in one;
   confirm the other session's board updates within a few seconds without a refresh.
