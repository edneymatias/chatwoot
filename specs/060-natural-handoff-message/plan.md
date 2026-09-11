# Implementation Plan: Natural Handoff Message

**Branch**: `060-natural-handoff-message` | **Date**: 2026-08-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/060-natural-handoff-message/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Make the assistant's own closing text for a turn become the customer-facing handoff message on
both existing handoff paths (explicit `handover_to_human` tool call, and the mechanical
opportunity-qualification trigger), instead of always showing the same fixed `I18n` sentence. This
requires generalizing `Custom::Scout::AgentRunner` so it always parses the model's structured
response *before* checking whether any tool flagged a handoff (today the `handover_to_human` path
short-circuits and returns before parsing, while the qualification path discards the parsed text
on purpose), then passing that parsed text through to `Custom::Scout::HandoffService`, which gains
an optional `message:` param and falls back to the existing fixed `I18n` string only when no usable
text is available. The `HandoverToHuman` tool changes from executing the handoff synchronously to
just flagging `handoff_needed` (duck-typed the same way `ManageOpportunity`/`MoveOpportunityStage`
already do), so `AgentRunner` can treat both handoff triggers uniformly. A new prompt guardrail
instructs the model to write a natural closing statement with no trailing question whenever a turn
ends in handoff. The `ActionClassifierService`-driven handoff path (Phase 12) and the system-failure
fail-safe path are explicitly left untouched, per the spec's assumptions.

## Technical Context

**Language/Version**: Ruby 3.x / Rails (this repo's existing Chatwoot fork stack)

**Primary Dependencies**: `RubyLLM` chat/tool-calling (already used by `AgentRunner`),
`Custom::Scout::ResponseSchema` (structured response schema), existing `Messages::MessageBuilder`,
`I18n`

**Storage**: N/A — no schema/data changes; only in-memory message routing within a single request

**Testing**: RSpec (`bundle exec rspec`), existing Scout spec suite under `custom/spec/services/custom/scout/`

**Target Platform**: Rails backend service (Sidekiq/inline job context where `AgentRunner` runs)

**Project Type**: Web service backend module (isolated `custom/` tree per this fork's Constitution
Principle I) — no frontend changes

**Performance Goals**: N/A — no new hot path or added external calls; same number of LLM
round-trips as today, just reordered parsing

**Constraints**: Must not change *which* mechanism decides a handoff is needed (FR-007); must never
show both the model text and the fixed sentence together (FR-002); must preserve existing "fail
closed" fallback behavior (FR-003, FR-006)

**Scale/Scope**: Single-conversation-turn scope; touches 4 existing files
(`agent_runner.rb`, `handoff_service.rb`, `tools/handover_to_human.rb`,
`system_prompts_service.rb`) plus their specs — no new files, no new tools, no new endpoints

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First** — PASS. All touched files already live under the isolated
  `custom/` tree (this fork's dedicated top-level module per the Constitution's own example), not
  in upstream `app/`. No upstream file is edited, renamed, or restructured. `ManageOpportunity`/
  `MoveOpportunityStage` (which already expose `handoff_needed`) are unaffected — `AgentRunner`
  reads a duck-typed attribute they already implement.
- **II. Smallest Production-Ready Change** — PASS. Reuses the existing `handoff_needed` duck-type
  already shared by `ManageOpportunity`/`MoveOpportunityStage` rather than inventing a new
  interface; adds one optional `message:` param to `HandoffService#perform`; no new abstractions,
  no speculative options. `perform_fail_safe_handoff` and the `ActionClassifierService` handoff
  path are explicitly left untouched (spec Assumptions / Out of scope), avoiding unnecessary blast
  radius.
- **III. Adhere to Established Conventions** — PASS. Pure Ruby service/tool changes following
  existing RuboCop conventions and the file's current style; no new user-facing template strings
  are introduced (the fixed `I18n` fallback string is reused as-is, no new translation keys
  needed), so no `en.yml`/`pt_BR.yml` sync is required by this feature.
- **IV. Safe, Reversible Change Management** — PASS. Local, reversible code + spec changes only; no
  destructive operations, no migrations, no CI/lint changes.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — PASS. `custom/` is this fork's own isolated
  module (not upstream `app/`), and there is no `enterprise/` equivalent of the Scout module to
  check — Scout is a fork-exclusive feature with no enterprise overlay counterpart.

No violations — Complexity Tracking section is not needed.

**Post-Phase 1 re-check**: Design artifacts (`research.md`, `data-model.md`, `quickstart.md`)
introduce no new files, no new abstractions, no persisted entities, and no touched files outside
`custom/`. All five gates above still PASS unchanged after design — no re-justification needed.

## Project Structure

### Documentation (this feature)

```text
specs/060-natural-handoff-message/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

No `contracts/` directory — this feature has no external interface (no new/changed HTTP endpoint,
public API, or CLI surface). It only changes internal Ruby object collaboration and one prompt
string within the existing Scout agent pipeline.

### Source Code (repository root)

```text
custom/
├── app/
│   └── services/
│       └── custom/
│           └── scout/
│               ├── agent_runner.rb              # generalize handoff detection, always parse first
│               ├── handoff_service.rb           # accept optional message:, fallback to fixed I18n text
│               ├── system_prompts_service.rb    # extend "Fallback para humano" guardrail bullet
│               └── tools/
│                   └── handover_to_human.rb      # flag handoff_needed instead of executing synchronously
└── spec/
    └── services/
        └── custom/
            └── scout/
                ├── agent_runner_spec.rb
                ├── handoff_service_spec.rb
                ├── system_prompts_service_spec.rb
                └── tools/
                    └── handover_to_human_spec.rb
```

**Structure Decision**: This is a backend-only change fully contained within the existing
fork-isolated `custom/` tree (per Constitution Principle I), mirroring the module layout Scout
already uses. No new files are created — all four touched services/tools already exist at the
paths above. No `frontend/`, `enterprise/`, or `db/migrate/` changes are needed: there is no UI
surface for this feature (the message shown to the customer is still rendered by the existing
conversation view), and Scout has no `enterprise/` overlay counterpart to keep in sync.

## Complexity Tracking

*No Constitution Check violations — this section is not applicable.*
