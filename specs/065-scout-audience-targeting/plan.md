# Implementation Plan: Scout Audience Targeting

**Branch**: `065-scout-audience-targeting` | **Date**: 2026-09-10 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/065-scout-audience-targeting/spec.md`

## Summary

Add an optional, per-Scout "target audience" (a flat list of AND/OR conditions over Contact
attributes, reusing the existing filter format) that gates whether a given Scout engages a
contact. When a Scout has no audience configured it keeps engaging everyone (no regression). When
it does, contacts outside the audience must never be left waiting on the Scout: their
conversations are routed to the normal human queue both when created and when a resolved
conversation is reopened. Matching is evaluated by a new `Custom::Scout::AudienceMatcherService`
and wired into the two existing status-determining hooks (`Conversation#determine_conversation_status`,
`Message#reopen_resolved_conversation`) via the fork's `custom/` override convention — composing
correctly with the Enterprise overlay modules that are also loaded and prepended onto the same
two classes (verified: not N/A, see Constitution Check §V). The audience is configured through a
new tab on the existing Scout detail screen, reusing `ConditionRow.vue` and
`useContactFilterContext()` — the same building blocks the existing Contacts filter UI
(`ContactsFilter.vue`) already uses — so no new frontend attribute plumbing is required (scoped to
contact attributes only; see spec Assumptions on deferring conversation-level attributes).

## Technical Context

**Language/Version**: Ruby 3.x (Rails 7.1, `chatwoot` core), Vue 3 (`<script setup>`, Composition API)

**Primary Dependencies**: Rails (ActiveRecord, `jsonb` column), existing fork `custom/` override
convention (`prepend_mod_with`/`include_mod_with`); frontend: `ConditionRow.vue` +
`useContactFilterContext()` (`app/javascript/dashboard/components-next/filter/`), Pinia store
pattern already used by `ScoutAPI`/other Scout tabs.

**Storage**: PostgreSQL — one new `jsonb` column `audience` (default `[]`) on the existing
`ichatr_scouts` table. No new tables.

**Testing**: RSpec (`bundle exec rspec`) for backend (service, model hook, controller specs);
`pnpm test` (Vitest) for the new Vue tab component.

**Target Platform**: Existing Chatwoot web dashboard + Rails API (self-hosted, Docker-composed
dev stack per `CLAUDE.md`).

**Project Type**: Web application (Rails API backend + Vue 3 SPA frontend), fork-specific module
under `custom/`.

**Performance Goals**: N/A beyond existing request/model-callback latency — audience evaluation is
an in-memory loop over a short admin-configured condition list (same order of magnitude as
existing `AutomationRules::ConditionsFilterService`); no new query load.

**Constraints**: Must not alter the shape or behavior of the two extended core hooks
(`determine_conversation_status`, `reopen_resolved_conversation`) for accounts/inboxes without a
Scout — the override activates only when `inbox.scout` is present and enabled. Because `custom`
modules are prepended after `enterprise` modules (`ChatwootApp.extensions = ['enterprise',
'custom']`), `Custom::Message`/`Custom::Conversation` sit closer to the front of the ancestor
chain and run first; `determine_conversation_status`'s override calls `super` unconditionally
before applying its own logic (matching the safe, already-proven pattern used by
`Custom::Inbox#active_bot?`/`Enterprise::Inbox#active_bot?`), so it composes correctly regardless
of module order. `reopen_resolved_conversation`'s override, when short-circuiting for a
non-matching contact, MUST still set `Current.executed_by = sender` for API-channel conversations
reopened by the contact (mirroring what `super`'s base-class branch would have done), so the
fork's own Opportunity/Kanban activity-log attribution isn't silently lost. A single condition
that can't be meaningfully compared MUST be treated as a local non-match (FR-007) — evaluation
MUST NOT swallow genuinely unexpected errors into a blanket "engage anyway," per this fork's
"fail loudly on misconfigured state" convention.

**Scale/Scope**: Single-account, single-Scout-per-inbox scope, matching the existing Scout model;
no explicit limit imposed on number of conditions per audience (mirrors the unbounded condition
lists already allowed in Kanban/Automation-Rule filters).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. All new backend code lives under `custom/` (new
  service, new `custom/app/models/custom/conversation.rb`, extended
  `custom/app/models/custom/message.rb`), plugging into the `prepend_mod_with`/`include_mod_with`
  hooks that `app/models/conversation.rb`/`app/models/message.rb` already call — zero edits to any
  core file. The new `audience` column lives on the fork-prefixed `ichatr_scouts` table, not a core
  table. Frontend additions live under the existing `components-next/Scout/pageComponents/` fork
  tree.
- **II. Smallest Production-Ready Change**: PASS. Reuses the existing flat-condition format,
  existing `ConditionRow.vue`/`useContactFilterContext()`, and the existing controller
  `permit`/`as_json` pattern; introduces one migration, one service, two small model overrides,
  one controller param addition, and one new Vue tab — no speculative abstraction (see spec
  Assumptions: no nested condition trees, no shared-module extraction of operator logic, no
  sampling/rollout-percentage mode).
- **III. Adhere to Established Conventions**: PASS. RuboCop-compliant Ruby, `<script setup>` Vue
  component, Tailwind-only styling, i18n keys added to both `en`/`pt_BR` `scout.json`, strong
  params via `permit`.
- **IV. Safe, Reversible Change Management**: PASS. Additive migration (new nullable-free column
  with a safe default, `null: false, default: []`), no destructive operations.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS, with a verified interaction documented (this
  gate is NOT a trivial N/A, correcting an earlier draft of this plan). `Scout` itself has no
  Enterprise equivalent, but `ChatwootApp.extensions` unconditionally loads `['enterprise',
  'custom']` in this install (`lib/chatwoot_app.rb`), so `Enterprise::Conversation` and
  `Enterprise::Message` are real, active modules prepended onto the exact two classes this feature
  also extends. No Enterprise file is edited, and the two modules compose safely (see Technical
  Context > Constraints for how each hook is designed to cooperate rather than silently shadow the
  other) — verified via research.md's audit rather than assumed.

No violations — Complexity Tracking table not needed.

*Post-design re-check (after Phase 1 data-model/contracts/quickstart): unchanged — no new files
outside `custom/`/the fork's `components-next/Scout/` tree were introduced, no core file bodies
are touched, and no new tables or shared-module extractions appeared during design. All five gates
still PASS.*

## Project Structure

### Documentation (this feature)

```text
specs/065-scout-audience-targeting/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   └── scouts-api.md
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
db/migrate/
└── <timestamp>_add_audience_to_ichatr_scouts.rb        # new — jsonb column, default []

custom/app/
├── services/custom/scout/
│   └── audience_matcher_service.rb                     # new — condition evaluation
├── models/
│   ├── scout.rb                                        # edit — add #engages?
│   └── custom/
│       ├── conversation.rb                             # new — first Conversation override in fork;
│       │                                                #   calls super unconditionally, then applies
│       │                                                #   the audience check (mirrors Custom::Inbox)
│       └── message.rb                                  # edit — override reopen_resolved_conversation;
│                                                        #   preserves Current.executed_by attribution
│                                                        #   on the short-circuit branch (see plan
│                                                        #   Technical Context > Constraints)
└── controllers/api/v1/accounts/
    └── scouts_controller.rb                            # edit — permit `audience` as
                                                          #   `[:attribute_key, :filter_operator,
                                                          #   :query_operator, { values: [] }]`
                                                          #   (see contracts/scouts-api.md)

app/javascript/dashboard/
├── components-next/Scout/pageComponents/
│   └── ScoutAudienceTab.vue                             # new — reuses ConditionRow.vue + contactProvider.js
│                                                          #   (same pieces ContactsFilter.vue already
│                                                          #   uses; NOT OpportunitiesFilter.vue, which
│                                                          #   uses the separate opportunityProvider.js)
├── routes/dashboard/scout/
│   ├── scout.routes.js                                  # edit — add a route entry for the new tab
│   └── pages/ScoutDetail.vue                            # edit — register new tab: tabIndexMap,
│                                                          #   currentTab, tabs computed, and
│                                                          #   handleTabChanged's routeMap (4 touch
│                                                          #   points, matching each existing tab)
└── i18n/locale/{en,pt_BR}/scout.json                    # edit — new "Público-Alvo"/"Target Audience" keys

custom/spec/
├── services/custom/scout/audience_matcher_service_spec.rb
├── models/
│   ├── custom/conversation_spec.rb
│   ├── custom/message_spec.rb
│   └── scout_spec.rb
└── controllers/api/v1/accounts/scouts_controller_spec.rb

app/javascript/dashboard/components-next/Scout/pageComponents/specs/
└── ScoutAudienceTab.spec.js
```

**Structure Decision**: Standard fork layout — all new domain code goes under `custom/app/**`
(backend) and the existing `components-next/Scout/` tree (frontend), matching every other Scout
phase already shipped in this codebase. `app/models/conversation.rb` already calls
`prepend_mod_with('Conversation')` (verified in the current codebase) with no
`custom/app/models/custom/conversation.rb` yet implementing it — this feature adds that file only;
**no core file needs to change at all**.

## Complexity Tracking

*No Constitution Check violations — table intentionally omitted.*
