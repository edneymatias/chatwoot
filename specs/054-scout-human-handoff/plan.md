# Implementation Plan: Scout Human Handoff on Manual Intervention

**Branch**: `054-scout-human-handoff` | **Date**: 2026-08-28 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/054-scout-human-handoff/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Prevent Scout from replying over a human agent who has already stepped in manually. When a human
agent sends a public reply to a `pending` conversation in a Scout-enabled inbox, the conversation
must synchronously transition to `open` before any already-queued Scout reply can be delivered —
mirroring the existing, proven mechanism Captain (Enterprise) already uses for the same problem.
The technical approach (see `research.md`) is to add one new file,
`custom/app/models/custom/message.rb`, prepended onto core `Message` via the extension point
already wired in (`Message.prepend_mod_with('Message')`), overriding
`mark_pending_conversation_as_open_for_human_response` to call `super` (preserving Captain's
existing behavior unchanged) and then apply the equivalent rule for Scout. No new endpoint, DB
field, or frontend change is introduced.

## Technical Context

**Language/Version**: Ruby (Rails), matching the existing `app/models/message.rb` /
`enterprise/app/models/enterprise/message.rb` conventions already in this repo.

**Primary Dependencies**: None new. Reuses Rails' `ActiveRecord` callbacks
(`after_create_commit`) and the repo's existing `prepend_mod_with` extension mechanism
(`config/initializers/01_inject_enterprise_edition_module.rb`).

**Storage**: N/A — no schema change; reuses existing `conversations.status`, `ichatr_scouts.enabled`,
`ichatr_scout_inboxes` columns/tables.

**Testing**: RSpec (`bundle exec rspec`), following existing conventions in `custom/spec/models/`.

**Target Platform**: Existing Chatwoot Rails backend (server-side only).

**Project Type**: Web service (Rails monolith) — backend-only change within it.

**Performance Goals**: N/A beyond "synchronous" (see Constraints) — this runs once per outgoing
message creation, same cost class as the existing Captain check it chains with.

**Constraints**: The conversation status transition MUST complete synchronously as part of
processing the human agent's message (same request/callback cycle), before any independently
queued/debounced Scout reply for that conversation can be delivered (FR-002, FR-003, SC-004).

**Scale/Scope**: Single new file (~20-30 lines), no migration, no new endpoint, no frontend change.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First** — PASS. Uses the existing `prepend_mod_with('Message')`
  extension point already unconditionally called in core `app/models/message.rb:460`; adds one new
  isolated file under `custom/app/models/custom/`; no core or enterprise file is edited. See
  `research.md` Decision 4.
- **II. Smallest Production-Ready Change** — PASS. One new file, no new abstraction beyond the
  minimum override + one predicate method; explicitly does not replicate Captain's extra side
  effects (activity message, `Current.user` reset, template-bootstrap guard) since the spec's
  scope is limited to the single backend mechanism. See `research.md` Decision 3.
- **III. Adhere to Established Conventions** — PASS. Compact `module`/`class` style, RuboCop
  150-char lines, mirrors the existing `Enterprise::Message` prepended-module pattern already in
  this codebase.
- **IV. Safe, Reversible Change Management** — PASS. Purely additive file; no destructive or
  irreversible operation involved.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — PASS, decision recorded: this feature does NOT
  edit `enterprise/app/models/enterprise/message.rb`. Scout is a fork-only concept orthogonal to
  Captain; the new `Custom::Message` module composes with `Enterprise::Message` via `super`
  (prepend order `[Custom::Message, Enterprise::Message, Message]`), so Captain's existing
  behavior is preserved unchanged and Scout's rule is layered on top independently. See
  `research.md` Decision 4.

No violations to record in Complexity Tracking.

**Post-Phase 1 re-check**: `data-model.md` and `quickstart.md` confirm no new entities, fields, or
endpoints were introduced during design — all five gates above still PASS unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/054-scout-human-handoff/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
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
│   └── models/
│       └── custom/
│           └── message.rb        # NEW — Custom::Message, prepended onto core Message
└── spec/
    └── models/
        └── custom/
            └── message_spec.rb   # NEW — RSpec coverage for the three user stories

app/models/message.rb             # UNCHANGED — already calls Message.prepend_mod_with('Message')
enterprise/app/models/enterprise/message.rb  # UNCHANGED — Captain behavior composes via super
```

**Structure Decision**: Single new file pair (implementation + spec) under the existing `custom/`
overlay, following the same `custom/app/models/custom/<name>.rb` +
`custom/spec/models/custom/<name>_spec.rb` layout already used for other prepended-module
overrides in this repo. No other directory or existing file needs to change.

## Complexity Tracking

Not applicable — no Constitution Check violations were identified (see above).
