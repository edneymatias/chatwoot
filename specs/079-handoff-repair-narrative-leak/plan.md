# Implementation Plan: Response Auditor Repair Loop Narrative Leak

**Branch**: `079-handoff-repair-narrative-leak` | **Date**: 2026-09-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/079-handoff-repair-narrative-leak/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command; its definition describes the execution workflow.

## Summary

Once `Custom::Scout::ResponseAuditor` already knows a turn's handoff was
deterministically decided by a successful `handover_to_human` tool call
(`@handoff_already_flagged == true`), it must stop treating that turn's reply
as unverified: skip `check_claim_consistency` and the repair loop entirely
and return the model's original reply and reason untouched. Today only the
action classifier is skipped for this condition (`evaluate_action`); the
claim-consistency check still runs, occasionally misjudges a coherent
handoff closing message as inconsistent, and triggers a repair call that
re-prompts the model with language implying a nonexistent prior failure —
which the model sometimes answers by apologizing for a fabricated mix-up and
calling the handoff tool a second time, overwriting the original correct
customer message and transfer note. The fix is a single additional guard in
`ResponseAuditor#audit`, mirroring the existing `evaluate_action` skip
pattern for the same flag (Decision 1/2, `research.md`). Independently, the
repair loop's outcome (reasoning + response) is logged whenever it does run,
closing the diagnostic blind spot that made this defect hard to trace
(Decision 3, `research.md`).

## Technical Context

**Language/Version**: Ruby 3.4.4 (Rails monolith; `.ruby-version`/`Gemfile`)

**Primary Dependencies**: Rails 7, RubyLLM (`chat.ask`, `RubyLLM::Chat`/`RubyLLM::Message`), RSpec 3

**Storage**: PostgreSQL (existing `conversations`/`messages` tables) — N/A for this feature; no schema change, no new table (see `data-model.md`)

**Testing**: RSpec, container-run: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/response_auditor_spec.rb` (targeted per Constitution Principle IX)

**Target Platform**: Linux server, rootless Podman/Docker Compose dev stack (per `AGENTS.md`)

**Project Type**: Web service (Rails monolith) — fork-specific module under `custom/`, mirroring the `enterprise/` overlay convention (Constitution Principle I)

**Performance Goals**: None explicitly required; incidental improvement — removes one wasted LLM call (`ClaimConsistencyService#check`) per tool-decided handoff turn (SC-002: 100% of such turns make zero additional consistency-check/repair calls)

**Constraints**: Change confined to the fork-owned `custom/` tree (no upstream/enterprise file touched); no new per-request parameter — reuse the existing `handoff_already_flagged` constructor argument already threaded by `AgentRunner`; no new user-facing strings, so no i18n sync needed

**Scale/Scope**: One file behaviorally changed (`custom/app/services/custom/scout/response_auditor.rb`, ~4-line net diff: one guard clause + repair-outcome logging), one spec file extended (`custom/spec/services/custom/scout/response_auditor_spec.rb`)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Upstream Compatibility First | PASS | `response_auditor.rb` is fork-original under `custom/`, confirmed no upstream or `enterprise/` equivalent exists (grep returned no matches). No extension point needed — there's nothing upstream to diverge from. |
| II. Smallest Production-Ready Change | PASS | One guard clause (skip check+repair when already flagged) plus one logging call in an already-open method (`execute_repair`). No refactor, no new abstraction, no speculative parameterization. |
| III. Adhere to Established Conventions | PASS | Mirrors the file's own existing `@handoff_already_flagged` skip pattern (`evaluate_action`) and the existing `[Scout AgentRunner] reasoning:` log-line convention (`agent_runner.rb:133`) for the new log line. RuboCop 150-char lines respected. |
| IV. Safe, Reversible Change Management | PASS | Local file edits + targeted spec run only; no destructive operations. |
| V. Dual-Tree Awareness (OSS + Enterprise) | PASS | No `enterprise/` Scout equivalent exists (verified); nothing to mirror. |
| VI. Test-Driven Development | PASS (planned) | New spec examples for the skip behavior (FR-001/002/003) and the repair-outcome log line (FR-006) will be written and observed failing before the guard/log line exist; full existing suite in the file proves FR-004/005 (no regression). |
| VII. Observable Behavior and Mutation Resistance | PASS | New assertions check `audit`'s real return value (`{ action: :proceed, reply: ... }` byte-identical to input) and that collaborator calls (`ClaimConsistencyService#check`, `chat.ask`) are not made — not internal method-call bookkeeping for its own sake. Doubling `ClaimConsistencyService`/`ActionClassifierService`/`chat` follows this same file's pre-existing, file-wide convention (these wrap the true external boundary: the LLM HTTP call) rather than introducing a new mocking style. |
| VIII. Pragmatic Test-First by Functional Slice | PASS | Guard, log line, and their tests are one cohesive functional slice (the full `audit`-skip behavior), not mechanically split into separate commits/steps. No step-journal artifacts created. |
| IX. Surgical Execution Scope | PASS | Validation scoped to `response_auditor_spec.rb` (and `agent_runner_spec.rb` for the caller-boundary check) during iteration; full suite reserved for pre-release per `quickstart.md`. |

No violations — Complexity Tracking table is empty (see below).

## Project Structure

### Documentation (this feature)

```text
specs/079-handoff-repair-narrative-leak/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md         # Phase 1 output (/speckit.plan command)
├── quickstart.md         # Phase 1 output (/speckit.plan command)
├── contracts/
│   └── response_auditor.md  # Phase 1 output (/speckit.plan command)
├── checklists/
│   └── requirements.md
└── tasks.md              # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
custom/
├── app/
│   └── services/
│       └── custom/
│           └── scout/
│               ├── response_auditor.rb      # MODIFIED: skip guard in #audit, logging in #execute_repair
│               ├── agent_runner.rb           # UNCHANGED: already passes handoff_already_flagged: tool.present?
│               ├── claim_consistency_service.rb  # UNCHANGED
│               └── handoff_service.rb        # UNCHANGED
└── spec/
    └── services/
        └── custom/
            └── scout/
                ├── response_auditor_spec.rb  # MODIFIED: new examples for skip behavior + repair-outcome logging
                └── agent_runner_spec.rb      # UNCHANGED: re-run only to confirm caller contract intact
```

**Structure Decision**: No new files, no new directories. The entire change
lives inside the existing fork-owned `custom/app/services/custom/scout/`
tree, which already has no upstream or `enterprise/` counterpart
(Constitution Principle I is satisfied trivially — there is nothing to keep
mergeable against, since this module is fork-original). Tests extend the
existing, colocated spec file rather than introducing a new one.

## Complexity Tracking

> No entries — Constitution Check reported no violations requiring justification.
