# Implementation Plan: Realtime Sync & Menu/Route Wiring

**Branch**: `004-realtime-sync-menu-wiring` | **Date**: 2026-07-31 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-realtime-sync-menu-wiring/spec.md`

## Summary

Close out the Kanban MVP by (1) broadcasting an `opportunity_updated` ActionCable event over the
existing account-level stream so any open board reflects changes live, (2) adding the two
genuinely missing menu/route wiring points (`dashboard.routes.js` for the board, and a
main-navigation Sidebar entry for it — the settings-side wiring was already committed ahead of
this phase), and (3) building `bin/sync-custom-module-hooks`, an idempotent, fail-fast, anchor-based
script whose manifest covers **every** shared/upstream file this project has touched so far —
not only the reachability files originally anticipated, but also the files already modified for
the automation-action integration (`featureFlags.js`, `useAutomationValues.js`,
`automationHelper.js`, `automation/constants.js`, and the i18n locale files) — so a future
upstream merge cannot silently drop any of it. The backend broadcast requires **zero core-file
edits**: it's a plain `after_commit` on the existing `custom/app/models/opportunity.rb`, calling
the existing `ActionCableBroadcastJob` directly rather than routing through the core
dispatcher/listener fan-out system, per Constitution Principle I.

## Technical Context

**Language/Version**: Ruby (Rails 7, matching `custom/app/models`), JavaScript (Vue 3.4
Composition API, matching `app/javascript/dashboard`).

**Primary Dependencies**: `ActionCableBroadcastJob` (existing, unmodified, core job) for the
backend broadcast; Vuex 4 (Phase 3's `opportunities` module, already built) for frontend state;
no new gems or npm packages.

**Storage**: N/A — no schema/migration changes in this phase.

**Testing**: `bundle exec rspec` (backend broadcast + sync-script specs), `pnpm test` (vitest,
`actionCable.spec.js` / opportunities store spec).

**Target Platform**: Rails backend (`rails` container) + browser dashboard SPA (`vite` container);
the sync script itself runs via `docker compose exec rails bin/sync-custom-module-hooks`.

**Project Type**: Web application — single Rails+Vue monorepo (no `frontend/`/`backend/` split).

**Performance Goals**: Live update delivered within a few seconds (SC-001: 5s) of the triggering
change, matching existing ActionCable broadcast latency for `contact.updated`/`conversation.updated`
— no new performance work required since the same job/queue (`ActionCableBroadcastJob`, `:critical`
queue) is reused as-is.

**Constraints**: Zero new core-file edits for the backend broadcast (Principle I); the sync
script's manifest is the single reviewable source of truth for every wiring edit (FR-013); the
script must fail loudly (non-zero exit, named file+anchor) rather than silently skip a broken
anchor (FR-006/FR-012).

**Scale/Scope**: One backend model callback (`custom/app/models/opportunity.rb`); one new
ActionCable event entry + handler in `actionCable.js`; one new route entry in
`dashboard.routes.js`; one new Sidebar main-nav menu item; one new Ruby CLI script
(`bin/sync-custom-module-hooks`) with a ~9-entry manifest (2 genuinely new wiring points + 7
already-applied ones now brought under the script's coverage).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First (NON-NEGOTIABLE)** — PASS. The backend broadcast lives
  entirely inside `custom/app/models/opportunity.rb` (an `after_commit` calling the existing,
  unmodified `ActionCableBroadcastJob` directly) — **no** core dispatcher, listener, or
  `Events::Types` file is touched (see `research.md` §2 for why the dispatcher/listener
  alternative was rejected). The frontend wiring is necessarily additive edits to shared files
  (`actionCable.js`, `Sidebar.vue`, `dashboard.routes.js`, plus the already-committed
  `settings.routes.js`/`store/index.js`/automation-integration files) — this is the one
  deliberate, spec-acknowledged exception to "isolate in `custom/`/dedicated trees," because
  Chatwoot's frontend has no `enterprise/`-style extension mechanism for menu/route/store
  registration (per spec.md Assumptions). The risk is mitigated by the sync script itself:
  anchor-based, minimal, single-line insertions, defined in one reviewable manifest, that fail
  loudly rather than silently drift.
- **II. Smallest Production-Ready Change** — PASS. Broadcasts on every create/update rather than
  building a field-allowlist (research.md §3); reuses the existing job/stream/mutation instead of
  new abstractions; the sync script's manifest is a flat array of hashes, not a templating engine.
- **III. Adhere to Established Conventions** — PASS. Ruby model callback follows existing
  `after_commit` idioms; Vue/Vuex edits reuse Phase 3's mutations; i18n/route/permission
  conventions (`meta.featureFlag`, `meta.permissions`) match `campaigns.routes.js` and
  `pipelineStages.routes.js`.
- **IV. Safe, Reversible Change Management** — PASS. All new edits are additive; the sync script
  is itself designed to be safely re-run (idempotent) and to fail safe (non-zero exit, no partial
  application) rather than risk silently corrupting a shared file.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — PASS, no action needed. No `enterprise/` override
  exists for `ActionCableListener`, `Sidebar.vue`, `dashboard.routes.js`, `settings.routes.js`, or
  `store/index.js` (confirmed by search); this phase's frontend files are OSS-only surfaces here,
  same finding as Phase 3.

No violations requiring Complexity Tracking.

**Post-Phase 1 re-check**: Design artifacts (`research.md`, `data-model.md`, `contracts/`)
confirmed the backend broadcast needs zero core-file edits and identified that 3 of the 5
originally-anticipated frontend files (plus 4 automation-integration files) were already committed
in Phase 3/earlier work — reducing this phase's *new* frontend edits to `dashboard.routes.js` and
the main-nav entry in `Sidebar.vue`, plus the new `actionCable.js` entry — with the sync script's
manifest additionally documenting the already-applied edits for future-merge safety. All five
gates remain PASS; no new violations introduced by this narrower-than-expected scope.

## Project Structure

### Documentation (this feature)

```text
specs/004-realtime-sync-menu-wiring/
├── plan.md              # This file
├── research.md           # Phase 0 output
├── data-model.md         # Phase 1 output
├── quickstart.md         # Phase 1 output
├── contracts/
│   ├── opportunity_updated_event.md
│   └── sync-script-cli.md
└── tasks.md              # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
custom/app/models/
└── opportunity.rb                                   # EDIT — add after_commit broadcast callback

bin/
└── sync-custom-module-hooks                          # NEW — Ruby CLI, manifest + --check/--apply

app/javascript/dashboard/
├── helper/actionCable.js                             # EDIT — 'opportunity_updated' event + handler
├── components-next/sidebar/Sidebar.vue               # EDIT — add main-nav board menu entry
│                                                       #        (Settings > Pipeline Stages entry
│                                                       #        already committed in Phase 3)
├── routes/dashboard/dashboard.routes.js               # EDIT — new `opportunities_index` route
└── routes/dashboard/settings/settings.routes.js       # already wired (Phase 3) — no edit needed

spec/models/opportunity_spec.rb                        # EDIT/NEW — after_commit broadcast spec
spec/bin/sync_custom_module_hooks_spec.rb              # NEW — script check/apply/fail-fast specs
app/javascript/dashboard/helper/specs/actionCable.spec.js  # EDIT — opportunity_updated handler spec
```

**Structure Decision**: Single Rails+Vue monorepo, matching Phases 1-3. The backend broadcast is
fully isolated inside `custom/` (one file, one callback). The sync script is a standalone `bin/`
executable with its manifest co-located in the same file (per FR-013), not a separate
config/data file, so the "one reviewable place" is literally one script. Frontend edits are
confined to the smallest possible additive insertions in the files not already wired
(`dashboard.routes.js`, and the main-nav entry in `Sidebar.vue`) plus the new `actionCable.js`
entry, per the audit in `research.md` §6.

## Complexity Tracking

No violations — table intentionally omitted (Constitution Check above records PASS on all five
gates with no exceptions requiring justification).
