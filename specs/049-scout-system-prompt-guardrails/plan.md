# Implementation Plan: Scout System Prompt Guardrails Architecture

**Branch**: `049-scout-system-prompt-guardrails` | **Date**: 2026-08-21 | **Spec**: [`spec.md`](file:///home/matias/dev/chatwoot/specs/049-scout-system-prompt-guardrails/spec.md)

**Input**: Feature specification from `specs/049-scout-system-prompt-guardrails/spec.md` and master documentation `docs/kanban/ciclo 10/scout/08-system-prompt-guardrails/spec71.md`.

---

## Summary

Extract prompt construction out of `Custom::Scout::AgentRunner` into a dedicated `Custom::Scout::SystemPromptsService` that wraps operator prompts inside fixed, unmodifiable domain and safety guardrails (identity/domain bounding, anti-hallucination, anti-false-promises, subordinate custom instructions in `<account_custom_instructions>`, and JSON response instructions). Standardize the response cycle in `AgentRunner` by channeling output through a single interception method (`process_response`) with markdown-fence sanitization, structured JSON parsing, observability logging for internal reasoning, and fail-closed human handoff when parsing fails.

---

## Technical Context

**Language/Version**: Ruby 3.3.x (Rails 7.1)  
**Primary Dependencies**: `RubyLLM` (v0.1.x), ActiveSupport, JSON stdlib  
**Storage**: PostgreSQL (No database migrations required; operates purely in memory & service orchestration)  
**Testing**: RSpec (`custom/spec/services/custom/scout/`)  
**Target Platform**: Linux container (Docker/Podman)  
**Project Type**: Backend service within isolated `custom/` module  
**Performance Goals**: Prompt assembly and JSON parsing overhead < 5ms per message cycle  
**Constraints**: Zero changes to core OSS files; 100% fail-closed parsing (zero raw token / reasoning leaks); 100% clean RuboCop (150-char line limit)  
**Scale/Scope**: Runtime per-message processing for all active Scout qualification conversations  

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evaluation & Rationale |
| :--- | :---: | :--- |
| **I. Upstream Compatibility First** | PASS | All changes live entirely within `custom/app/services/custom/scout/` and `custom/spec/`. Zero edits to core `app/` or `enterprise/` trees. |
| **II. Smallest Production-Ready Change** | PASS | Minimal, direct implementation: 1 new prompt service, refactored runner with 1 single interception method. No speculative second-pass LLM auditors or unnecessary DB migrations. |
| **III. Adhere to Established Conventions** | PASS | Follows Ruby conventions, compact class definitions, 150-char RuboCop rules, and explicit service delegation. |
| **IV. Safe, Reversible Change Management** | PASS | Non-destructive service changes fully covered by unit and integration specs. |
| **V. Dual-Tree Awareness (OSS + Enterprise)** | PASS | Scout is a custom module; architectural parity maintained with Enterprise Captain patterns without modifying enterprise code. |

---

## Project Structure

### Documentation (this feature)

```text
specs/049-scout-system-prompt-guardrails/
├── spec.md              # Feature specification
├── plan.md              # Implementation plan
├── research.md          # Technical research & decisions
├── data-model.md        # Runtime schemas and lifecycle
├── quickstart.md        # Verification and quickstart guide
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── contracts/
    ├── system-prompts-service-contract.md
    └── agent-runner-interception-contract.md
```

### Source Code (repository root)

```text
custom/
├── app/
│   └── services/
│       └── custom/
│           └── scout/
│               ├── system_prompts_service.rb  # [NEW] Guardrail system prompt builder
│               └── agent_runner.rb            # [MODIFIED] Single interception point + JSON parser
└── spec/
    └── services/
        └── custom/
            └── scout/
                ├── system_prompts_service_spec.rb # [NEW] Prompt template unit tests
                └── agent_runner_spec.rb           # [MODIFIED] Structured output & fail-closed tests
```

**Structure Decision**: Code is isolated within the `custom/` hierarchy, preserving standard Chatwoot conventions.

---

## Complexity Tracking

> **No Constitution violations detected. All gates passed.**

| Violation | Why Needed | Simpler Alternative Rejected Because |
| :--- | :--- | :--- |
| *None* | N/A | N/A |
