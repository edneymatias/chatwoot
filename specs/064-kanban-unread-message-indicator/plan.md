# Implementation Plan: Kanban Unread Message Indicator (Post-Handoff Only)

**Branch**: `064-kanban-unread-message-indicator` | **Date**: 2026-09-10 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/064-kanban-unread-message-indicator/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Add a small, real-time "unread message" dot to a Kanban card, but only for opportunities the human
team already owns: it must stay hidden while `Opportunity#scout_engaged?` is true, and appear only
once Scout has handed the conversation off (or was never engaged) and there is an unread incoming
customer message. Technical approach: derive a new `has_unread_messages?` boolean on `Opportunity`
that is explicitly gated by `!scout_engaged?`, expose it in `as_json`, and generalize the
broadcast/rename mechanism already built for the "Scout" badge (Phase 22) so the same real-time
pipe refreshes both derived fields — adding a second `after_commit` trigger on `Conversation`
(read state) and a new `Custom::Concerns::Message` trigger (new incoming message), since neither of
those events touches `Conversation#status` (the only column the existing trigger watches).

## Technical Context

**Language/Version**: Ruby (Rails, per repo's existing `Gemfile`), Vue 3 (Composition API,
`<script setup>`)

**Primary Dependencies**: Existing Chatwoot core models (`Conversation#unread_incoming_messages`,
`agent_last_seen_at`), existing fork infra from Phase 22 (`ActionCableBroadcastJob`,
`Opportunity#scout_engaged?`, the `custom/app/models/custom/concerns/` extension pattern), Tailwind
(no new dependency)

**Storage**: N/A — no new persisted column; `has_unread_messages?` is a derived, computed value
(not stored), consistent with `scout_engaged?`

**Testing**: RSpec (`bundle exec rspec`) for Ruby models/concerns, Vitest (`pnpm test`) for the Vue
component

**Target Platform**: Existing Chatwoot web dashboard (Kanban board), same account-scoped
ActionCable channel already used for the "Scout" badge

**Project Type**: Web application (Rails backend + Vue frontend, existing monolith — no new
project/service)

**Performance Goals**: Real-time update perceived by the agent within 5 seconds of the underlying
change (read, new message, handoff) — see spec.md SC-003 — matching the existing "Scout" badge's
broadcast latency, no new performance target beyond that.

**Constraints**: Must reuse, not duplicate, the Phase 22 broadcast mechanism (Constitution
Principle II — smallest production-ready change; also explicit user preference already recorded in
the source design doc). No new unread-message-counting logic — reuse
`Conversation#unread_incoming_messages` as-is (Principle II). Must not alter the existing "Scout"
badge's visual behavior.

**Scale/Scope**: Single UI affordance (one `<span>` dot) on one existing component
(`KanbanCard.vue`); two small `after_commit` hooks; one new concern file
(`custom/app/models/custom/concerns/message.rb`).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. No upstream/core file is edited. The only touch point
  in a core-adjacent file is `Message.include_mod_with('Concerns::Message')` in
  `app/models/message.rb`, which **already exists** (line 464) — this feature only needs to create
  the concern file it already looks for, matching the same convention as
  `Custom::Concerns::Conversation`. All new logic lives under `custom/`.
- **II. Smallest Production-Ready Change**: PASS. Reuses `unread_incoming_messages`,
  `agent_last_seen_at`, and the Phase 22 broadcast job as-is. The only "new" mechanism is two
  additional `after_commit` triggers, which is the minimum needed to cover the two state
  transitions (new message, read) that the existing single trigger (`saved_change_to_status?`)
  cannot observe. The Phase 22 methods are renamed (not duplicated) to reflect their now-broader
  purpose, per the source design doc's explicit decision to avoid a second parallel broadcast path.
- **III. Adhere to Established Conventions**: PASS. Ruby concern follows the existing
  `Custom::Concerns::*` pattern; Vue changes stay in the existing `<script setup>` /
  Composition-API component; the dot uses a Tailwind utility class with an arbitrary duration value
  (`animate-pulse [animation-duration:3s]`), not custom CSS; new user-facing string
  (`UNREAD_TOOLTIP`) goes into `en.json`/`pt_BR.json` per the i18n rule.
- **IV. Safe, Reversible Change Management**: PASS. Purely additive/renaming change to
  fork-owned files; no destructive operations, no schema migration.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS (no action needed). `Opportunity`,
  `Custom::Concerns::Conversation`, and the Kanban board are fork-owned (`custom/` and
  `components-next/Opportunities/`) with no corresponding `enterprise/` override to keep in sync —
  same conclusion already reached and recorded by Phase 22 for the identical broadcast mechanism.

No violations. Complexity Tracking section is not needed.

## Project Structure

### Documentation (this feature)

```text
specs/064-kanban-unread-message-indicator/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

No `contracts/` directory: this feature adds no new externally-consumed API, endpoint, or schema —
it extends an existing internal `as_json` payload and an existing internal ActionCable broadcast
that are both private implementation details of the Kanban board, not a public contract.

### Source Code (repository root)

```text
custom/
├── app/
│   └── models/
│       ├── opportunity.rb                        # rename broadcast method + add has_unread_messages?
│       └── custom/concerns/
│           ├── conversation.rb                    # add agent_last_seen_at to existing after_commit guard
│           └── message.rb                         # NEW — after_commit on create for incoming, non-private messages
└── spec/
    └── models/
        └── custom/concerns/
            ├── conversation_spec.rb               # agent_last_seen_at triggers broadcast
            └── message_spec.rb                    # NEW — incoming/non-private message triggers broadcast

spec/
└── models/
    └── opportunity_spec.rb                        # has_unread_messages? cases (incl. scout_engaged? gating)

app/javascript/dashboard/
├── components-next/Opportunities/
│   ├── KanbanCard.vue                             # add unread dot, gated on opportunity.has_unread_messages
│   └── specs/KanbanCard.spec.js                   # dot rendering cases
└── i18n/locale/
    ├── en/opportunities.json                      # BOARD.UNREAD_TOOLTIP
    └── pt_BR/opportunities.json                   # BOARD.UNREAD_TOOLTIP
```

**Structure Decision**: No new top-level structure. This is a small, additive change entirely
within the existing fork-owned `custom/` tree (backend) and the existing
`components-next/Opportunities/` tree (frontend), following the same file layout Phase 22 already
established for the sibling "Scout" badge feature.

## Complexity Tracking

*No violations — section not applicable.*
