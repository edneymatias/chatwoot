# Implementation Plan: Contact Memory Handoff Pretext Guardrail

**Branch**: `077-contact-memory-handoff-guardrail` | **Date**: 2026-09-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/077-contact-memory-handoff-guardrail/spec.md`

## Summary

Scout currently reads a contact's durable memory notes (`contact.notes`, injected into every new
conversation's system prompt via `Custom::Scout::SystemPromptsService#contact_context_section`) as
if each note were an active fact of the current turn. A note recorded from a past, already-resolved
"I want a human" request therefore leaks into a brand-new conversation and, by itself, justifies a
premature `handover_to_human` even though the current conversation contains no such request
(reproduced in production: conv 45006 citing conv 44877's note three days later). The fix is a
prompt-instruction guardrail plus note dating, both confined to `custom/`:

1. **Just-in-time memory-interpretation warning** — a new conditional paragraph in
   `contact_context_section`, emitted whenever `@contact.notes.any?`, in the same `AVISO:`
   just-in-time pattern as `identity_warning`/`phone_request_warning`. It states notes are summaries
   of prior, concluded conversations (not current-turn facts); MAY/SHOULD be used to personalize and
   proactively anticipate (including nudging toward scheduling); but NEVER on their own justify
   `handover_to_human` — the transfer signal must come from the current conversation's own messages.
2. **Origin date on newly generated notes** — `Custom::Scout::ContactNotesService#generate_and_update_notes`
   prefixes each persisted note's content with a human-readable date (e.g. `[22/09/2026] …`) before
   `@contact.notes.create!`. Because the shared upstream `LlmFormatter::ContactLlmFormatter#build_notes`
   renders `note.content` verbatim, the date surfaces automatically in Scout's prompt and in the
   dashboard's contact Notes view (accepted overlap) with no upstream edit. Not retroactive.

No new tool, model, schema, migration, or deterministic trigger (FR-008). The interpretation and
the transfer decision remain Scout's own judgment, steered by updated instructions. The Phase 12
`ResponseAuditor`/`ActionClassifierService` safety net is untouched (FR-007).

## Technical Context

**Language/Version**: Ruby 3.x (Rails), matching the existing `custom/` service layer.

**Primary Dependencies**: RubyLLM (`Scout#llm_chat`), existing `Custom::Scout::*` service tree; no
new gems.

**Storage**: PostgreSQL via existing `notes` table (`Note` belongs_to contact). No schema change —
only the free-text `content` value gains a leading date on new rows.

**Testing**: RSpec under `custom/spec/` (container: `docker compose exec rails env -u FRONTEND_URL
RAILS_ENV=test bundle exec rspec`). Behavioral replay via `Custom::Scout::PlaygroundRunner`, the
convention used by prior guardrail phases (23, 29).

**Target Platform**: Linux server (container-based dev, rootless Podman).

**Project Type**: Web application (Rails backend + Vue frontend); this feature is backend-only,
inside the fork's isolated `custom/` overlay. No frontend change (the dashboard Notes view already
renders `note.content` verbatim, so the embedded date appears there without UI work).

**Performance Goals**: N/A — one extra string prefix per note and one extra conditional prompt
paragraph; negligible.

**Constraints**: No edit to any upstream/shared file (esp. `app/services/llm_formatter/contact_llm_formatter.rb`,
shared with Captain). No retroactive rewrite of pre-existing notes (#41–53). No new tool/model/schema
(FR-008). Genuine present-turn human requests must keep handing off immediately with zero regression.

**Scale/Scope**: Two `custom/` files edited, two `custom/spec/` files extended. Affects only
accounts/assistants with `scout.feature_memory?` enabled (only they generate/receive notes).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First (NON-NEGOTIABLE)** — PASS. Both edits live entirely in the
  fork's isolated `custom/` overlay (`system_prompts_service.rb`, `contact_notes_service.rb`). The
  shared upstream formatter is deliberately left untouched by prefixing the date into `note.content`
  at generation time; it renders verbatim, so no coupling to `ContactLlmFormatter` is introduced.
- **II. Smallest Production-Ready Change** — PASS. One conditional prompt paragraph + one string
  prefix. Note de-duplication / reinforcement-loop suppression (preview §5, scope item 3) is
  explicitly rejected as over-engineering: FR-001/FR-002's revised interpretation neutralizes the
  loop without touching note generation. No speculative guards or feature flags.
- **III. Adhere to Established Conventions** — PASS. Reuses the existing `AVISO:` just-in-time
  warning pattern (`identity_warning`, `phone_request_warning`) in the same method; pt-BR copy to
  match Scout's operating language; RuboCop-clean private-method extraction.
- **IV. Safe, Reversible Change Management** — PASS. Purely additive, reversible edits; no
  destructive operations, no data migration.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — PASS. `Custom::Scout::*` is fork-original with no
  `enterprise/` counterpart to mirror. The Captain twin (`Captain::Llm::ContactNotesService`) is
  intentionally out of scope — this guardrail is Scout-specific and does not alter any OSS/Enterprise
  request/response contract. Recorded here per the dual-tree decision requirement.
- **VI. Test-Driven Development (NON-NEGOTIABLE)** — PASS (planned). Each behavior change lands a
  test that fails first: a `system_prompts_service_spec` example for the memory warning (present with
  notes, absent without), and a `contact_notes_service_spec` example for the date prefix on persisted
  `content`. The existing `notes eq [...]` assertion is updated to the dated contract. Acceptance
  scenarios are additionally exercised through the real entry point via `PlaygroundRunner` replay.
- **VII. Observable Behavior and Mutation Resistance (NON-NEGOTIABLE)** — PASS. Prompt-text and
  persisted `content` are observable outputs asserted directly; the notes spec's existing external
  LLM boundary double (`RubyLLM::Chat`) is the only mock, and the assertions verify real persisted
  DB state, not mock echoes.
- **VIII. Pragmatic Test-First by Functional Slice** — PASS. Delivered as one cohesive slice
  (guardrail paragraph + dating + their specs), no step-journals.
- **IX. Surgical Execution Scope** — PASS. Iterate against the two targeted spec files only; full
  suite reserved for pre-integration.

**Result**: PASS — no violations, Complexity Tracking not required.

## Project Structure

### Documentation (this feature)

```text
specs/077-contact-memory-handoff-guardrail/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   ├── memory-warning-prompt.md
│   └── memory-note-format.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
custom/
├── app/services/custom/scout/
│   ├── system_prompts_service.rb     # EDIT: add memory-interpretation AVISO paragraph in
│   │                                 #       contact_context_section (guarded by @contact.notes.any?)
│   └── contact_notes_service.rb      # EDIT: prefix "[DD/MM/YYYY] " onto each note before create!
└── spec/services/custom/scout/
    ├── system_prompts_service_spec.rb  # EDIT: new examples — warning present w/ notes, absent w/o
    └── contact_notes_service_spec.rb   # EDIT: assert dated content; update existing eq assertion

# Untouched, referenced for context:
app/services/llm_formatter/contact_llm_formatter.rb   # upstream/shared — renders note.content verbatim, NOT edited
custom/app/services/custom/scout/handoff_service.rb   # calls generate_contact_memory on handoff — NOT edited
custom/app/services/custom/scout/response_auditor.rb  # Phase 12 safety net — NOT edited (FR-007)
```

**Structure Decision**: Backend-only change inside the fork's isolated `custom/` overlay, mirroring
the existing `Custom::Scout::SystemPromptsService` / `Custom::Scout::ContactNotesService` layout and
their sibling specs. No frontend, migration, or shared-file changes. This is the single prompt entry
point where memory reaches Scout, so the guardrail is not duplicated elsewhere.

## Complexity Tracking

> No Constitution Check violations — section intentionally empty.
