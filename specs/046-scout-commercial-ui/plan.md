# Implementation Plan: Scout Commercial Configuration UI

**Branch**: `046-scout-commercial-ui` | **Date**: 2026-08-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/046-scout-commercial-ui/spec.md`

## Summary

Give account admins and agents a dashboard UI, living in a new primary-menu "Scout" section
(mirroring this fork's existing `Opportunities` module, not Settings), to configure Scouts end to
end: list/create/edit, inbox association, product catalog, commercial knowledge base (URLs,
PDF uploads, FAQs), funnel/qualification stage mapping, external tool (`ScoutTool`) CRUD, and a
Playground that always executes real tool calls (native and external) without persisting a real
Chatwoot conversation. LLM provider/API-key configuration stays on a separate, admin-only Settings
screen. Backend: new Rails controllers/policies under `custom/`, two new additive tables
(`ichatr_scout_knowledge_sources`, `ichatr_scout_required_fields`), no changes to core `app/` or
`enterprise/`. Frontend: new Vue 3 + Tailwind screens under
`app/javascript/dashboard/routes/dashboard/scout/` and `components-next/Scout/`, wired into
`dashboard.routes.js` and `Sidebar.vue` behind a new `FEATURE_FLAGS.SCOUT` flag, with `en`/`pt_BR`
translations added synchronously.

## Technical Context

**Language/Version**: Ruby (Rails, this repo's pinned version) for backend; JavaScript (Vue 3,
Composition API + `<script setup>`) for frontend, per `CLAUDE.md`.

**Primary Dependencies**: Existing `Scout`/`ScoutInbox`/`ScoutTool` models and
`Scout::AgentRunner`/native tools (Phases 01-04, `custom/app/**`); `ruby_llm` (already a Gemfile
dependency, used indirectly via `AgentRunner`); Pundit (`ApplicationPolicy`); `ActiveStorage`
(mirroring `Captain::Document`'s PDF handling) for knowledge-base document uploads; Vue Router,
existing `components-next/` design-system primitives, `frontendURL` helper, `i18n` (`vue-i18n`).

**Storage**: PostgreSQL. Two new additive tables under the fork's `ichatr_` prefix
(`ichatr_scout_knowledge_sources`, `ichatr_scout_required_fields`); existing `ichatr_scouts`
(`product_catalog` jsonb), `ichatr_scout_inboxes`, `ichatr_scout_tools` reused as-is. See
`data-model.md`.

**Testing**: RSpec (`docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec
rspec custom/spec/...`) for backend; Vitest (`docker compose exec vite pnpm test`) for frontend,
per `CLAUDE.md`. Per `CLAUDE.md`/constitution, specs are only written when explicitly requested —
this plan does not mandate spec authorship in `/speckit-tasks`, but any specs written must follow
`custom/spec/` conventions already in place (e.g. `custom/spec/models/scout_spec.rb`).

**Target Platform**: Existing Chatwoot dashboard (web), inside this Rails+Vue monorepo — no new
deployable service.

**Project Type**: Web application (Rails API backend + Vue 3 SPA frontend), extending an existing
monorepo; not a new project structure.

**Performance Goals**: No feature-specific targets beyond standard dashboard responsiveness
(existing Chatwoot dashboard interaction budgets); Playground round trips depend on the LLM
provider's and any external tool endpoint's own latency, which is out of this feature's control.

**Constraints**: Must not modify `app/` or `enterprise/` files (Principle I/V) — all Ruby lives
under `custom/`, all new frontend code lives under fork-owned directories following the
`Opportunities`-module precedent, not interleaved into upstream Vue directories. Must mirror
Captain's UI/permission *shape* (primary menu for business config, admin-only Settings for
provider/API key) without adopting Captain's plan/licensing gating (this fork has no plan
dimension for Scout — see `research.md` §5). i18n: `en.json`/`pt_BR.json` and `en.yml`/`pt_BR.yml`
updated synchronously, no bare strings (Principle III / FR-011).

**Scale/Scope**: 6 primary-menu screens (list/edit, products, knowledge base, funnel config,
tools, playground) + 1 admin-only Settings screen; no cap on products/knowledge-sources/tools per
Scout (clarified as unlimited).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Status |
|---|---|---|
| I. Upstream Compatibility First | All new Ruby under `custom/`; new tables use `ichatr_` prefix; only touches `config/routes.rb` (fixed Rails location, additive) outside `custom/`. Frontend follows the `Opportunities` module's existing precedent for a fork-owned primary-menu section (new files under fork-owned paths + minimal, additive edits to `dashboard.routes.js`/`Sidebar.vue`/`featureFlags.js`, same shape as the existing `opportunities` entries) rather than restructuring shared upstream directories. | PASS |
| II. Smallest Production-Ready Change | `product_catalog` stays jsonb (no new table) since it has no file/async concerns; only knowledge sources (file upload + async status) and qualification fields (reuse of an existing pattern) get new tables, each justified in `research.md`. Playground reuses `AgentRunner` internals via an explicit `playground:` flag instead of a parallel implementation or unpersisted-object approach (research.md §4). | PASS |
| III. Adhere to Established Conventions | Controllers/policies mirror `PipelineStagesController`/`PipelineStagePolicy` exactly; Vue components use Composition API + `<script setup>`, Tailwind-only styling, PascalCase components; i18n added synchronously in `en`/`pt_BR`. | PASS |
| IV. Safe, Reversible Change Management | New migrations are additive (new tables only, no altered/dropped upstream tables); no destructive operations planned. | PASS |
| V. Dual-Tree Awareness (OSS + Enterprise) | Scout is a fork-owned (`custom/`) feature with no Enterprise counterpart to keep in sync — Captain (Enterprise) is used only as a UI/permission-shape reference, not extended or modified. | PASS (N/A — no `enterprise/` change) |

No violations requiring `Complexity Tracking` justification.

## Project Structure

### Documentation (this feature)

```text
specs/046-scout-commercial-ui/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── rest-api.md      # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
db/migrate/
├── 21260819XXXXXX_create_ichatr_scout_knowledge_sources.rb   # next free suffix after 000006
└── 21260819XXXXXX_create_ichatr_scout_required_fields.rb     # per existing 21260819NNNNNN scout migrations

config/routes.rb                        # additive: scouts, scout_tools, nested resources
config/features.yml                     # additive: new `scout` flag entry (backend registration
                                         # for FEATURE_FLAGS.SCOUT — see research.md §5)

custom/app/
├── controllers/api/v1/accounts/
│   ├── scouts_controller.rb
│   ├── scout_tools_controller.rb
│   └── scouts/
│       ├── scout_inboxes_controller.rb
│       ├── product_catalog_items_controller.rb
│       ├── knowledge_sources_controller.rb
│       ├── provider_settings_controller.rb   # admin-only
│       └── playground_messages_controller.rb
├── models/
│   ├── scout_knowledge_source.rb
│   └── scout_required_field.rb
├── policies/
│   ├── scout_policy.rb
│   ├── scout_tool_policy.rb
│   └── scout_knowledge_source_policy.rb
├── services/custom/scout/
│   ├── agent_runner.rb           # MODIFIED: accept `playground:` flag; read knowledge sources from
│   │                              # the new association instead of jsonb (research.md §2, §4)
│   ├── playground_runner.rb
│   └── tools/                    # MODIFIED: CreatePrivateNote, UpdateContact, ManageOpportunity,
│                                  # MoveOpportunityStage, HandoverToHuman each gain a `playground:`
│                                  # branch that skips persistence (research.md §4)
└── jobs/custom/scout/knowledge_sources/
    └── process_job.rb            # single-page fetch / PDF extraction only, no Captain::* reuse
                                   # (research.md §2)

custom/spec/  # mirrors the above, only if specs are explicitly requested

app/javascript/dashboard/
├── featureFlags.js                      # add FEATURE_FLAGS.SCOUT (additive line, paired with the
│                                         # config/features.yml `scout` entry above)
├── routes/dashboard/dashboard.routes.js  # additive: import + register scout routes
├── routes/dashboard/scout/
│   ├── scout.routes.js
│   └── pages/ (list, create/edit, products tab, knowledge base tab, funnel tab, tools, playground)
├── routes/dashboard/settings/scout/
│   ├── scout.routes.js                  # admin-only provider/API key screen
│   └── Index.vue
├── components-next/Scout/               # new, mirrors components-next/Opportunities/ + components-next/captain/ shape
│   ├── pageComponents/
│   └── composables/
├── components-next/sidebar/Sidebar.vue  # additive: new "Scout" menu entry (feature-flag gated)
├── api/scout/                           # mirrors api/captain/*.js per-resource API clients
├── i18n/locale/en/scout.json / pt_BR/scout.json (or equivalent existing i18n grouping)
└── i18n/locale/en.yml / pt_BR.yml       # backend-facing strings if any surface via API errors
```

**Structure Decision**: Extends the existing Rails + Vue monorepo using this fork's two proven
precedents — `custom/` for all new Ruby (already the location of every prior Scout phase) and the
`Opportunities` module's frontend wiring pattern for a new primary-menu section (already the only
non-Captain, fork-owned primary-menu precedent in this codebase). No new top-level project/package
is introduced.

## Complexity Tracking

*No Constitution Check violations — table intentionally left empty.*
