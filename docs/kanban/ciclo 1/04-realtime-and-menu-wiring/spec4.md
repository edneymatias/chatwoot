# Phase 4: Realtime Sync & Menu/Route Wiring

**Depends on**: Phase 1 (backend model + `after_commit`/dispatcher hooks), Phase 3 (Vuex store + components must exist to be wired in and to receive the realtime event)
**Feeds**: nothing (final phase)

## Context

Two unrelated but co-located concerns close out the MVP:

1. **Realtime sync**: Opportunity is no longer derived from Conversation, so the old design's free ride on `conversation.updated` ActionCable broadcasts doesn't apply. A new `opportunity_updated` event must be dispatched over the **existing per-account ActionCable channel** (not a new channel) and consumed by the frontend.
2. **Menu/route wiring**: since no frontend equivalent of `enterprise/`'s backend extension mechanism exists, the board and settings screens built in Phase 3 must be registered into 5 known core files: `Sidebar.vue`, `dashboard.routes.js`, `settings.routes.js`, `store/index.js`, `actionCable.js`. These are the only core-file touches in the entire frontend build.

Because `actionCable.js` is a highly volatile upstream file (frequent changes to connection lifecycle/memory-leak fixes), the injection into it (and the other 4 files) is done via a scripted, anchor-based, fail-fast sync mechanism rather than a blind manual/scripted append — so that a future upstream restructuring of these files breaks the build loudly instead of silently dropping realtime sync or menu entries.

## Dev Environment

Backend verification runs inside the `rails` container (`docker compose exec rails <command>`), frontend verification inside the `vite` container (`docker compose exec vite <command>`). The sync script (`bin/sync-custom-module-hooks`) is a Ruby script under `bin/`, so it MUST be invoked as `docker compose exec rails bin/sync-custom-module-hooks ...`. `git` commands run directly on the host, since the repo is bind-mounted into both containers and the host already has a working git checkout.

## Functional Requirements

**FR-001**: Backend — on `Opportunity` create/update (via an `after_commit` callback on the model, or a dedicated listener subscribing to a new dispatcher event, consistent with the existing `app/dispatchers`/`app/listeners` pattern), broadcast `opportunity_updated` on the **same account-level ActionCable channel** already used for other account broadcasts (identify and reuse the exact channel class/stream name already in use — do not create a new `ActionCable::Channel` subclass). Payload MUST include at minimum: `id`, `pipeline_stage_id`, `status`, `contact_id`, `assignee_id`, `updated_at` — enough for the frontend to patch its normalized store without a follow-up fetch.

**FR-002**: Frontend — `actionCable.js`'s `this.events` object MUST gain one new entry: `'opportunity_updated': this.onOpportunityUpdated`, with a handler that dispatches into the Phase 3 Vuex module (moving the card between `cardIdsByStage` arrays and upserting `cardsById`, using the same mutations already built in Phase 3 — no new mutation logic invented here).

**FR-003**: The following 5 core files require additive, minimal edits:
- `app/javascript/dashboard/helper/actionCable.js` — new event entry (FR-002).
- `app/javascript/dashboard/components/layout/sidebar/Sidebar.vue` (or current equivalent path) — new menu item linking to the Kanban board route, gated by the `opportunities` feature flag (Phase 1 FR-012).
- `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` — new route(s) for `KanbanBoard.vue`.
- `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js` — new route(s) for the Pipeline Stages settings screen.
- `app/javascript/dashboard/store/index.js` — register the Phase 3 `opportunities` Vuex module.

**FR-004**: A sync script (e.g. `bin/sync-custom-module-hooks`) MUST exist that performs these 5 injections idempotently (re-running it after it has already applied is a no-op, not a duplicate insertion) and is intended to be run once per upstream merge/rebase in the user's future fresh-checkout workflow.

**FR-005**: For each of the 5 files, the script MUST locate an **exact anchor string** already present in the current version of that file (e.g., the literal existing line `'conversation.updated': this.onConversationUpdated,` in `actionCable.js`) and insert the new entry adjacent to it (same indentation/style as surrounding code) — never a blind end-of-file or blind top-of-array append.

**FR-006**: If any anchor string is not found in a target file, the script MUST exit non-zero immediately with a clear error message naming the file and the missing anchor, and MUST NOT partially apply the remaining injections for that file. This is a hard fail-fast requirement: a broken sync must break the build/CI visibly, never silently skip the injection and let a stale/unsynced state reach production.

**FR-007**: The script's anchor definitions (file path + anchor string + text to insert) MUST live in a single, easily-reviewed data structure (e.g., a JSON/YAML manifest or a plain array of hashes at the top of the script) rather than scattered inline logic, so future maintenance (e.g., updating an anchor after an intentional upstream rename) is a one-line diff.

**FR-008**: The script MUST be runnable both as a dry-run (`--check`, prints what would change / confirms anchors still exist, without writing) and as an apply run (default or `--apply`) — the dry-run mode is what the user will run first after every fresh upstream checkout to detect drift before touching files.

## Out of Scope (this phase)

- Any new ActionCable channel class (reuses the existing account channel).
- Automating the `custom/` backend `eager_load_paths` line from Phase 1 (that's a one-time infra change, not part of the recurring-sync problem this script solves — only the 5 frontend files are in scope here, since `custom/app/**` backend code never requires per-upstream-merge re-injection).

## Completion Criteria

1. **Realtime broadcast fires** (FR-001) — verify via `docker compose exec rails rails console` + a websocket listener, or via a request spec run with `docker compose exec rails bundle exec rspec ...`:
   ```ruby
   # in a test/console session with an ActionCable test adapter
   opp = Opportunity.first
   expect { opp.update!(pipeline_stage_id: other_stage.id) }
     .to have_broadcasted_to(account_channel_stream).with(hash_including(event: 'opportunity_updated'))
   ```
   Adapt `account_channel_stream` to whatever the existing account channel stream identifier actually is (found via `Explore` on `app/channels` before writing this test).

2. **Frontend event handling** (FR-002): `docker compose exec vite pnpm test` on an `actionCable.spec.js`/store spec asserting that receiving an `opportunity_updated` payload moves the card's id between the correct `cardIdsByStage` arrays and updates `cardsById[id]` in place.

3. **Sync script dry-run detects a clean baseline**: on the current branch (all 5 files present and un-modified by hand), run:
   ```
   docker compose exec rails bin/sync-custom-module-hooks --check
   ```
   Must report all 5 anchors found, zero drift, exit code 0.

4. **Sync script apply is idempotent** (FR-004):
   ```
   docker compose exec rails bin/sync-custom-module-hooks --apply
   git diff --stat   # run on the host — shows the 5 expected additive edits
   docker compose exec rails bin/sync-custom-module-hooks --apply
   git diff --stat   # identical to previous run — no duplicate insertions
   ```

5. **Fail-fast behavior proven** (FR-006) — deliberately corrupt one anchor to simulate an upstream rename, e.g.:
   ```
   sed -i "s/'conversation.updated': this.onConversationUpdated,//" app/javascript/dashboard/helper/actionCable.js
   docker compose exec rails bin/sync-custom-module-hooks --check
   echo $?   # must be non-zero
   ```
   Confirm the error message names the exact file and missing anchor. Revert the deliberate corruption afterward (`git checkout -- app/javascript/dashboard/helper/actionCable.js`).

6. **End-to-end manual verification** (menu/route wiring, FR-003): with the feature flag enabled for a test account, log in, confirm the sidebar shows the new menu entry, clicking it loads the Kanban board at its route, Settings shows the Pipeline Stages screen at its route, and opening two browser sessions on the same account — dragging a card in one session — updates the other session's board within a few seconds without a manual refresh (proves FR-001+FR-002 end-to-end, not just unit-tested in isolation).
