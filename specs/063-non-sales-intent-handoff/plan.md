# Implementation Plan: Non-Sales Intent Recognition and Immediate Handoff

**Branch**: `063-non-sales-intent-handoff` | **Date**: 2026-09-10 | **Spec**: [`spec.md`](spec.md)

**Input**: Feature specification from `specs/063-non-sales-intent-handoff/spec.md` and master
documentation `docs/kanban/ciclo 10/scout/23-non-sales-intent-immediate-handoff/spec86.md`.

## Summary

Add one new bullet to `Custom::Scout::SystemPromptsService#guardrails_section` — a proactive
"non-prospecting intent recognition" guardrail placed immediately after the existing "Fallback
para humano" bullet — instructing Scout to call `handover_to_human` immediately whenever the
contact's own words make clear they are not seeking a new prospecting evaluation (already a
customer, ongoing treatment, reschedule/cancel, complaint, or a "just a quick question" answer to
a triage question), without first attempting to resolve the request itself. The guardrail also
notes that an optional externally configured customer-status tool (already available generically
via `Custom::Scout::Tools::CallCustomApi` / `ScoutTool` from Fase 04) may be consulted to reinforce
the decision when the phone number is available, but its absence or a non-positive result never
blocks the handoff. This is a pure prompt-text change: no new tool, model, migration, or change to
the existing reactive `ActionClassifierService` safety net (Fase 12).

## Technical Context

**Language/Version**: Ruby 3.3.x (Rails 7.1)

**Primary Dependencies**: None new — reuses the existing `Custom::Scout::SystemPromptsService`
prompt builder and the existing `handover_to_human` tool already referenced by the "Fallback para
humano" guardrail

**Storage**: N/A — no database change; the guardrail is static prompt text

**Testing**: RSpec (`custom/spec/services/custom/scout/system_prompts_service_spec.rb`); manual
behavioral replay via `Custom::Scout::PlaygroundRunner`; repo-wide `bin/sync-custom-module-hooks
--audit` gate per `CLAUDE.md` Release Process (expected no-op here, since the only file touched is
fork-original with no upstream/enterprise equivalent to protect)

**Target Platform**: Linux container (Docker/Podman), same runtime as the rest of Scout

**Project Type**: Backend service text change within the isolated `custom/` module

**Performance Goals**: N/A — adds a fixed, small string to an existing prompt-assembly method;
no measurable overhead beyond current prompt construction

**Constraints**: Zero changes to core OSS/enterprise files; zero new tools/models/migrations; must
not alter the existing reactive Response Auditor (`ActionClassifierService`) behavior; 100% clean
RuboCop (150-char line limit)

**Scale/Scope**: Applies to every Scout conversation on every account (the guardrail is part of
the fixed system prompt built for all accounts); no per-account configuration or flag

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evaluation & Rationale |
| :--- | :---: | :--- |
| **I. Upstream Compatibility First** | PASS | The only file touched is `custom/app/services/custom/scout/system_prompts_service.rb` (already a fork-owned file inside `custom/`), plus its spec. No core `app/` or `enterprise/` file is touched. |
| **II. Smallest Production-Ready Change** | PASS | A single new guardrail bullet, matching the exact text already decided in `spec86.md`. No new tool, table, migration, service, or abstraction — explicitly ruled out in the source phase doc. |
| **III. Adhere to Established Conventions** | PASS | Follows the existing guardrail bullet format (`- Label: sentence.`) already used by every other bullet in `guardrails_section`; RuboCop 150-char line limit respected via heredoc line wrapping as done for neighboring bullets. |
| **IV. Safe, Reversible Change Management** | PASS | Purely additive text change, fully reversible by removing the bullet; covered by a new RSpec example plus manual `PlaygroundRunner` replay before release. |
| **V. Dual-Tree Awareness (OSS + Enterprise)** | PASS | Scout is a fork-only (`custom/`) module with no enterprise equivalent; no enterprise file requires a matching change. |

No violations — Complexity Tracking is not needed.

## Project Structure

### Documentation (this feature)

```text
specs/063-non-sales-intent-handoff/
├── spec.md               # Feature specification
├── plan.md               # This file (/speckit-plan command output)
├── research.md           # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md         # Phase 1 output (/speckit-plan command)
├── checklists/
│   └── requirements.md   # Spec quality checklist
└── tasks.md              # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

No `contracts/` directory is generated — this feature exposes no new external interface (no new
endpoint, tool schema, or public method signature); the only "contract" is the guardrail's plain
text, which is captured directly in `data-model.md`/`quickstart.md`.

### Source Code (repository root)

```text
custom/
├── app/
│   └── services/
│       └── custom/
│           └── scout/
│               └── system_prompts_service.rb  # [MODIFIED] guardrails_section: +1 bullet
└── spec/
    └── services/
        └── custom/
            └── scout/
                └── system_prompts_service_spec.rb  # [MODIFIED] +1 example asserting the bullet
```

**Structure Decision**: Single-file change inside the existing fork-owned `custom/` tree, mirroring
the layout already used by every prior Scout system-prompt phase (e.g. `049-scout-system-prompt-
guardrails`, `052-scout-qualification-gate`). No new directories, services, or layers are
introduced.

## Complexity Tracking

> **No Constitution violations detected. All gates passed.**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| *None* | N/A | N/A |
