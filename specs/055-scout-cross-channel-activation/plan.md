# Implementation Plan: Scout Cross-Channel Activation

**Branch**: `055-scout-cross-channel-activation` | **Date**: 2026-08-28 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/055-scout-cross-channel-activation/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Fix two independent root causes that silently restrict Scout to WhatsApp-only inboxes, even though
that restriction was never a stated product requirement. (1) `Custom::ScoutListener` — the sole
entry point that enqueues `Custom::Scout::ProcessMessageJob` — gates on
`inbox&.channel_type == 'Channel::Whatsapp'`; removing that gate lets it process incoming public
messages on any channel, as long as the inbox has an enabled Scout. (2) New conversations never
start `pending` on any Scout-enabled inbox (WhatsApp included, in a real, non-factory-forced
scenario) because `Conversation#determine_conversation_status` only flips to `pending` when
`Inbox#active_bot?` is true, and `Inbox#active_bot?` only knows about the legacy
`agent_bot_inbox`/Dialogflow mechanism — it has never heard of Scout. The technical approach (see
`research.md`) mirrors the exact pattern Captain (Enterprise) already uses for the identical
problem: a new `custom/app/models/custom/inbox.rb`, prepended onto core `Inbox` via the
already-wired `Inbox.prepend_mod_with('Inbox')` extension point, overriding `active_bot?` to
`super || scout_active?`. Per the clarified spec, this is forward-only — no backfill/migration
touches conversations that already exist at deploy time.

## Technical Context

**Language/Version**: Ruby (Rails), matching the existing `app/models/inbox.rb` /
`enterprise/app/models/enterprise/inbox.rb` conventions already in this repo.

**Primary Dependencies**: None new. Reuses the repo's existing `prepend_mod_with` extension
mechanism (`config/initializers/01_inject_enterprise_edition_module.rb`) and the existing
`Events::Base`/Wisper-style listener dispatch already driving `Custom::ScoutListener`.

**Storage**: N/A — no schema change; reuses existing `conversations.status`, `ichatr_scouts.enabled`,
`ichatr_scout_inboxes` columns/tables (same entities as Phase 10 / `specs/054-scout-human-handoff`).

**Testing**: RSpec (`bundle exec rspec`), following existing conventions in
`custom/spec/listeners/` and `custom/spec/models/`.

**Target Platform**: Existing Chatwoot Rails backend (server-side only).

**Project Type**: Web service (Rails monolith) — backend-only change within it.

**Performance Goals**: N/A — this removes a conditional and adds one more `||` branch to an
already-cheap, per-message-creation callback and per-conversation-creation check; no new query
pattern or hot path is introduced.

**Constraints**: The fix MUST NOT alter conversation-creation status for inboxes with no Scout
linked, or a disabled Scout (FR-003); MUST NOT touch the legacy `agent_bot_inbox`/Dialogflow branch
(FR-004); MUST NOT retroactively change already-existing conversations (FR-008, per clarification).

**Scale/Scope**: One line removed in an existing file, one new ~10-line file
(`custom/app/models/custom/inbox.rb`), no migration, no new endpoint, no frontend change.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First** — PASS. `Inbox.prepend_mod_with('Inbox')` is already
  unconditionally called in core `app/models/inbox.rb:288`; the new `Custom::Inbox` module is
  purely additive under `custom/app/models/custom/`. The listener change removes a conditional
  inside an already fork-owned file (`custom/app/listeners/custom/scout_listener.rb`) — no core or
  enterprise file is edited. See `research.md` Decision 1 and Decision 3.
- **II. Smallest Production-Ready Change** — PASS. The listener fix is a one-line deletion; the
  Inbox fix is the minimum override (`active_bot?` + one private predicate) needed to satisfy
  FR-002, with no speculative helper methods beyond what the existing `scout_listener.rb` /
  `custom/app/models/custom/message.rb` call sites already established as the idiom
  (`inbox.scout&.enabled?`). No backfill/migration code is added, per the spec's forward-only
  clarification (FR-008) — see `research.md` Decision 4.
- **III. Adhere to Established Conventions** — PASS. Compact `module`/`class` style, RuboCop
  150-char lines, mirrors the existing `Enterprise::Inbox`/`Custom::Message` prepended-module
  pattern already in this codebase.
- **IV. Safe, Reversible Change Management** — PASS. Both changes are small, purely additive or
  subtractive-of-a-guard-clause; no destructive or irreversible operation, no migration.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — PASS, decision recorded: this feature does NOT
  edit `enterprise/app/models/enterprise/inbox.rb`. Scout is a fork-only concept orthogonal to
  Captain; the new `Custom::Inbox#active_bot?` composes with `Enterprise::Inbox#active_bot?` via
  `super` (prepend order `[Custom::Inbox, Enterprise::Inbox, Inbox]`, same ordering already proven
  in Phase 10's `Custom::Message`/`Enterprise::Message` composition), so Captain's existing
  behavior is preserved unchanged and Scout's rule is layered on top independently. See
  `research.md` Decision 2.

No violations to record in Complexity Tracking.

**Post-Phase 1 re-check**: `data-model.md` and `quickstart.md` confirm no new entities, fields, or
endpoints were introduced during design — all five gates above still PASS unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/055-scout-cross-channel-activation/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

No `contracts/` directory: this feature is purely internal (no new endpoint, public API, or
frontend contract) — see Outline step 2 ("Skip if project is purely internal").

### Source Code (repository root)

This is a Rails monolith (Chatwoot); the change lives entirely in the fork's isolated `custom/`
overlay tree, mirroring the `enterprise/` convention per Constitution Principle I.

```text
custom/
├── app/
│   ├── listeners/
│   │   └── custom/
│   │       └── scout_listener.rb        # MODIFIED — remove the Channel::Whatsapp gate
│   └── models/
│       └── custom/
│           └── inbox.rb                 # NEW — Custom::Inbox, prepended onto core Inbox
└── spec/
    ├── listeners/
    │   └── custom/
    │       └── scout_listener_spec.rb   # MODIFIED — flip 'ignores non-WhatsApp inboxes' to a
    │                                    # positive cross-channel assertion (spec Scope item 3)
    └── models/
        └── custom/
            └── inbox_spec.rb            # NEW — RSpec coverage for Custom::Inbox#active_bot?

app/models/inbox.rb                      # UNCHANGED — already calls Inbox.prepend_mod_with('Inbox')
enterprise/app/models/enterprise/inbox.rb # UNCHANGED — Captain behavior composes via super
app/models/conversation.rb               # UNCHANGED — determine_conversation_status already calls
                                          # inbox.active_bot? generically; no channel-specific logic
                                          # lives here
custom/app/models/custom/message.rb      # UNCHANGED — Phase 10 handoff already depends only on
                                          # conversation.pending? + inbox.scout&.enabled?, agnostic
                                          # to channel (spec Acceptance Criteria, User Story 3)
custom/spec/models/custom/message_spec.rb # MODIFIED — add cross-channel regression case (User
                                          # Story 3 / FR-006, task T009)
```

**Structure Decision**: Two small, isolated changes: one guard-clause removal in an already
fork-owned listener, and one new file pair (implementation + spec) under the existing `custom/`
overlay, following the same `custom/app/models/custom/<name>.rb` +
`custom/spec/models/custom/<name>_spec.rb` layout Phase 10 (`Custom::Message`) already established
for prepended-module overrides. No core or enterprise file changes.

## Complexity Tracking

Not applicable — no Constitution Check violations were identified (see above).
