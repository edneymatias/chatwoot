# Implementation Plan: Routine-Request Guardrail False Positive & Persona Precedence Fix

**Branch**: `071-scout-guardrail-precedence-fix` | **Date**: 2026-09-15 | **Spec**: specs/071-scout-guardrail-precedence-fix/spec.md

**Input**: Feature specification from `/specs/071-scout-guardrail-precedence-fix/spec.md`

## Summary

`Custom::Scout::SystemPromptsService#guardrails_section`'s "Reconhecimento de intenção fora de
prospecção" bullet currently introduces its non-prospecting examples with "ex.:" (non-exhaustive),
so the model over-generalizes a low-complexity/routine new request into the "quick question, not
prospecting" pattern and hands off instead of qualifying. The fix rewrites that bullet to an
exhaustive "apenas quando:" (only when:) criteria list — existing customer with product/service in
progress, changing/cancelling something that already exists, a complaint, or a purely informational
question with no new-product/service signal — and adds an explicit carve-out stating a
low-complexity/preventive/recurring/no-specific-problem new request is still a valid new opportunity
that follows the normal funnel. Separately, `#custom_instructions_section`'s precedence sentence
currently subordinates account persona instructions to the entire guardrails block as one monolithic
"security rule" unit, so no persona wording can ever change this classification bullet. The fix
names the specific non-negotiable guardrails (anti-hallucination, JSON response format,
anti-false-promise, action confirmation) that persona instructions can never override, and adds one
named exception: persona instructions may refine or expand what counts as valid commercial intent
specifically for the "Reconhecimento de intenção fora de prospecção" bullet. Both edits are in-place
text changes to existing heredocs in one file; no new tool, model, schema, or deterministic handoff
trigger is introduced (FR-008).

## Technical Context

**Language/Version**: Ruby 3.4.4 (repo `.ruby-version`), Rails (existing Gemfile version) — unchanged

**Primary Dependencies**: None added. Reuses the existing `RubyLLM`-backed `Scout#llm_chat` /
`Custom::Scout::PlaygroundRunner` chat path already used by prior Scout prompt features.

**Storage**: N/A — no schema, model, or migration change (FR-008); `Scout#system_prompt` (persona)
is an existing column, read but not modified by this feature.

**Testing**: RSpec, `custom/spec/services/custom/scout/system_prompts_service_spec.rb`, run via
`docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec` per
`.specify/memory/tdd-profile.md` and Constitution Principle VI (test-first: spec assertions are
updated/added before the prompt text they assert on changes, and observed failing for the right
reason before the implementation edit lands).

**Target Platform**: Rails backend service inside the container-based dev stack
(`docker compose up -d` — `rails`, `vite`, `sidekiq`, `postgres`, `redis`), per `AGENTS.md`.

**Project Type**: Single project (Rails monolith); change confined entirely to the fork-owned
`custom/` tree (Constitution Principle I — no upstream/`app/` or `enterprise/` file touched).

**Performance Goals**: N/A — prompt text edit only, no throughput/latency requirement.

**Constraints**:
- RuboCop `Layout/LineLength` (Max 150, `.rubocop.yml:19-20`) does not apply to either edited line:
  both are inside `<<~SECTION` heredocs, and RuboCop's `Layout/LineLength` cop defaults
  `AllowHeredoc: true` (confirmed: no override in `.rubocop.yml`/`.rubocop_todo.yml`, and the
  existing unmodified bullets are already 700-1200+ chars on one physical line) — no backslash
  continuation needed.
- Guardrail wording MUST stay domain-agnostic — zero medical/dental/segment-specific vocabulary
  (FR-003, SC-004).
- Zero new tools, data models, schema changes, or mechanical/deterministic handoff triggers (FR-008)
  — classification stays entirely model-judgment-driven from the prompt text.
- No Enterprise counterpart exists for `Custom::Scout::SystemPromptsService` (verified: `enterprise/`
  only has the unrelated `Captain::Llm::SystemPromptsService`, a different AI assistant) — Principle
  V dual-tree check has nothing to mirror.

**Scale/Scope**: 2 files modified, 0 files created (beyond this feature's own `specs/` docs):
- `custom/app/services/custom/scout/system_prompts_service.rb` — 2 single-line heredoc bullets
  rewritten in place (`guardrails_section` line 78, `custom_instructions_section` line 168 per the
  current read; re-anchor on the literal bullet text if line numbers have drifted).
- `custom/spec/services/custom/scout/system_prompts_service_spec.rb` — 5 existing examples updated
  (stale substring assertions), 3 new examples added (FR-002 carve-out, FR-004/005 persona-refines-
  guardrail exception, FR-004/006 non-negotiable-guardrails-still-protected).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. Both edits are inside `custom/app/services/custom/scout/`,
  a fork-owned file with no upstream equivalent; no core/`app/` file touched.
- **II. Smallest Production-Ready Change**: PASS. Exactly the 2 bullets FR-001–FR-006 require are
  touched; the other 7 guardrail bullets (Intenção Comercial, Esclarecimento, Identidade do contato,
  Ritmo e condução da conversa, Respeito ao ritmo do lead, Fallback para humano, Idioma e Estilo)
  are explicitly left untouched per FR-004's clarification-session scope decision.
- **III. Established Conventions**: PASS. RuboCop heredoc exemption confirmed above; spec follows
  existing `it`/`expect(prompt).to include(...)` convention already used throughout the file.
- **IV. Safe, Reversible Change Management**: PASS. Local file edits + `git commit`, no destructive
  operation.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS. No Enterprise override exists for this class
  (confirmed above) — nothing to mirror.
- **VI. Test-Driven Development (NON-NEGOTIABLE)**: PASS, procedurally enforced by
  `.specify/extensions.yml`'s `before_implement` mandatory `speckit.tdd.run` hook. This plan's task
  breakdown (produced later by `/speckit.tasks`, out of scope here) must still sequence spec updates
  before the prompt-text edit they assert on, per Technical Context's Testing note.

No violations — Complexity Tracking table omitted (nothing to justify).

## Project Structure

### Documentation (this feature)

```text
specs/071-scout-guardrail-precedence-fix/
├── spec.md                          # already exists
├── checklists/requirements.md       # already exists
├── plan.md                          # this file
├── research.md                      # Phase 0 output
├── data-model.md                    # Phase 1 output
└── quickstart.md                    # Phase 1 output
```

No `contracts/` directory: `Custom::Scout::SystemPromptsService` has no external interface (HTTP
API, CLI, wire schema) for this feature — it is an internal prompt-string builder consumed only by
`Custom::Scout::AgentRunner`/`PlaygroundRunner` in-process.

### Source Code (repository root)

```text
custom/
├── app/
│   └── services/
│       └── custom/
│           └── scout/
│               └── system_prompts_service.rb   # guardrails_section + custom_instructions_section edited
└── spec/
    └── services/
        └── custom/
            └── scout/
                └── system_prompts_service_spec.rb   # assertions updated/added
```

**Structure Decision**: Single project, fork-owned `custom/` tree only (mirrors every prior Scout
prompt feature — 059/060/061/23). No frontend, no new directories.
