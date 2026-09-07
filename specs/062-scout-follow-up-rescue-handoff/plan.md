# Implementation Plan: Scout Follow-Up Nudges and Rescue Handoff

**Branch**: `062-scout-follow-up-rescue-handoff` | **Date**: 2026-09-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/062-scout-follow-up-rescue-handoff/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

A periodic job scans `pending` Scout conversations for silence, sends up to two deterministic
(non-LLM) re-engagement nudges on an account-configurable ascending delay schedule, and — if the
contact is still silent at the final threshold — moves the linked open opportunity to an
account-configured "rescue" pipeline stage and hands the conversation off to a human via the
existing `Custom::Scout::HandoffService`. Attempt count is derived from message history (no new
counter column). The job respects the inbox's business hours (`OutOfOffisable#out_of_office?`) and
re-checks `pending?` immediately before acting to avoid racing a contact/human reply. A related
race window in `Custom::Scout::AgentRunner#process_audited_reply` (between the response auditor
call and dispatch/handoff) is closed with an extra `conversation_pending?` re-check. The deal board
gets a "Scout" badge on cards whose active conversation is currently pending on the contact.

## Technical Context

**Language/Version**: Ruby 3.x (Rails 7.2), Vue 3 (Composition API, `<script setup>`)

**Primary Dependencies**: Rails/ActiveRecord, Sidekiq (`config/schedule.yml` cron jobs), existing
fork services — `Custom::Scout::HandoffService`, `OutOfOffisable` concern (core), `Messages::MessageBuilder`

**Storage**: PostgreSQL — additive columns on the existing `ichatr_scouts` table
(`rescue_stage_id` FK to `ichatr_pipeline_stages`, `follow_up_delays_hours` jsonb); no new tables

**Testing**: RSpec (`custom/spec/jobs`, `custom/spec/models`, `custom/spec/controllers`,
`custom/spec/services`), `spec/configs/schedule_spec.rb`; Vitest for `KanbanCard.vue`

**Target Platform**: Existing Chatwoot Rails monolith + Vue dashboard, Sidekiq cron (`scheduled_jobs` queue)

**Project Type**: Web application (Rails backend + Vue frontend) — fork-specific module under `custom/`

**Performance Goals**: Runs every 30 minutes (`config/schedule.yml` cron cadence); must complete a
scan of all enabled Scouts' stalled conversations well within that window (existing scheduled-job
pattern, no new SLA)

**Constraints**: Deterministic, no LLM call anywhere in the nudge/handoff decision path (per
`spec80.md` precedent); attempt count fixed at 2 in this phase; must not add a counter column
(derive attempts from message history); must not alter `Opportunity#status`, only `pipeline_stage_id`

**Scale/Scope**: Per-account Scout automation; bounded by existing `pending` conversation volume
per inbox — no new indexing beyond what `Conversation.pending` / `last_activity_at` already support

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. All new code lives under the fork's own `custom/`
  tree (`Custom::Scout::FollowUpJob`) mirroring the existing `Custom::Scout::ProcessMessageJob`
  sibling; the only touches to shared/core-adjacent files are additive (`config/schedule.yml` new
  cron entry, `i18n` new keys, `Opportunity#as_json` new derived field, `KanbanCard.vue` new
  conditional badge) plus one behavioral fix inside the fork's own
  `Custom::Scout::AgentRunner`. No upstream file is restructured or renamed. Reuses the core
  `OutOfOffisable` concern rather than reinventing business-hours logic.
- **II. Smallest Production-Ready Change**: PASS. Attempt count is fixed (no speculative
  configurability), attempts are derived from existing message history (no new counter
  column/migration for state that already exists), and the rescue stage is a new nullable
  optional field following the exact pattern already used for `qualified_stage_id`/`unqualified_stage_id`.
- **III. Adhere to Established Conventions**: PASS, with one correction from the source design
  doc — this fork's existing Scout migrations (`db/migrate/21260819000005_...`,
  `21260828230000_...`) use explicit `up`/`down` methods with `change_table bulk: true` and a
  separate `add_foreign_key ... on_delete: :nullify` call, not `ActiveRecord::Migration[7.1]`
  `change` + `add_reference` shorthand. The plan's migration MUST follow the established `up`/`down`
  + `change_table` + `add_foreign_key` pattern for consistency (see `research.md`). i18n additions
  are added synchronously in `en.yml`/`pt_BR.yml` and `en/opportunities.json`/`pt_BR/opportunities.json`.
- **IV. Safe, Reversible Change Management**: PASS. Migration is additive-only (new nullable FK
  column + new jsonb column with a default), reversible via a `down` method; no destructive
  operations.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS — no Enterprise equivalent exists for Scout
  (a fork-only feature under `custom/`), so no Enterprise override/extension point is needed. The
  one core file touched, `OutOfOffisable`, is read-only reuse (calling `#out_of_office?`), not
  modified.

## Project Structure

### Documentation (this feature)

```text
specs/062-scout-follow-up-rescue-handoff/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
db/migrate/
└── <timestamp>_add_rescue_stage_and_follow_up_delays_to_ichatr_scouts.rb   # additive columns, up/down

custom/app/models/
└── scout.rb                                    # + rescue_stage assoc, follow_up_delays_hours validation

custom/app/controllers/api/v1/accounts/
└── scouts_controller.rb                        # + rescue_stage_id, follow_up_delays_hours[] permitted params

custom/app/jobs/custom/scout/
└── follow_up_job.rb                            # new: Custom::Scout::FollowUpJob

custom/app/services/custom/scout/
└── agent_runner.rb                             # process_audited_reply: add post-audit pending? re-check

custom/app/models/
└── opportunity.rb                              # + scout_engaged? / as_json field

config/
├── schedule.yml                                # + custom_scout_follow_up_job cron entry
└── locales/{en,pt_BR}.yml                      # + scout.follow_up_nudge, scout.follow_up_handoff

app/javascript/dashboard/
├── components-next/Opportunities/KanbanCard.vue   # + "Scout" badge, conditioned on scout_engaged
└── i18n/locale/{en,pt_BR}/opportunities.json      # + BOARD.SCOUT_BADGE

custom/spec/
├── jobs/custom/scout/follow_up_job_spec.rb
├── services/custom/scout/agent_runner_spec.rb  # + auditor race-window scenario
├── models/scout_spec.rb                        # + rescue_stage validation
└── controllers/api/v1/accounts/scouts_controller_spec.rb  # + rescue_stage_id param

spec/configs/schedule_spec.rb                   # existing generic schedule.yml validation, no changes expected

app/javascript/dashboard/components-next/Opportunities/specs/
└── KanbanCard.spec.js                          # + Scout badge render/omit cases
```

**Structure Decision**: Existing single Rails-monolith-plus-Vue-dashboard layout, unchanged. All
new domain logic is additive and lives inside the fork's own `custom/` tree (mirroring
`Custom::Scout::ProcessMessageJob`), per Constitution Principle I. The two files under core paths
(`config/schedule.yml`, `Opportunity#as_json`, `KanbanCard.vue`, locale files) receive only
additive edits (new cron entry, new derived JSON field, new conditional badge, new i18n keys); the
one core service touched for behavior (`AgentRunner`) is itself a fork-owned file under `custom/`,
not upstream core.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

None — the Constitution Check above found no violations across all 5 principles.
