# Implementation Plan: Scout Contact Identity Detection

**Branch**: `061-scout-contact-identity` | **Date**: 2026-09-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/061-scout-contact-identity/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Website-widget visitors who haven't identified themselves get an auto-generated placeholder
contact name (`Haikunator.haikunate(1000)`, shape `adjective-noun-number`, e.g.
`empty-meadow-50`), but Scout (the AI sales agent) never notices this and never asks for the real
name — confirmed in two real qualification conversations. This feature adds a small,
namespace-isolated helper that classifies a contact's name as a system-generated placeholder by
shape (regex, no fixed word list), and uses it to (a) inject a conditional warning + "ask for the
name, as early as possible — ideally in the first response, and with priority over any pending
qualification question" instruction into the per-contact system-prompt context section for
website-widget contacts, and (b) add a channel-agnostic guardrail bullet telling Scout to use the
same judgment/priority on non-website channels where no deterministic signal exists (2026-09-02
clarifications). No new tool is introduced — saving the real name once given reuses the existing
`update_contact` tool. No core `Contact` model code is touched. `Custom::Scout::PlaygroundRunner`
also gains a small optional `contact:` param so the spec's own replay-based verification step is
actually runnable (see `research.md`). The clarified "never ask in a handoff-ending turn" rule
(FR-011) requires **no restatement** of the existing "no questions when transferring" rules
(`guardrails_section`/`handoff_closing_reminder_section`) — confirmed by re-reading the current
`system_prompts_service.rb`. A dispatched alignment audit against the code and prior Scout
guardrail specs (2026-09-02) surfaced two concrete wording risks that this plan now accounts for:
(1) the new instructions must state they're exempt from `funnel_section`'s "only ask about
configured fields" guidance (new FR-013), and (2) given a documented 2026-08-30 production
regression of "asked a question and transferred in the same turn," both new insertion points carry
one short cross-reference clause subordinating them to the handoff rule — a targeted mitigation, not
new architecture (see `research.md`).

## Technical Context

**Language/Version**: Ruby (Rails app, per repo `Gemfile`/`.ruby-version` — no new language/runtime introduced)

**Primary Dependencies**: None new. Reuses existing `Haikunator` (already a runtime dependency via `ContactInboxWithContactBuilder`), the existing `Custom::Scout::SystemPromptsService`, and the existing `Custom::Scout::Tools::UpdateContact` tool.

**Storage**: N/A — no schema/migration changes; reads the existing `contacts.name` column only, no new persisted state.

**Testing**: RSpec (`custom/spec/services/custom/scout/`), following existing conventions in that directory (`let`-based setup, `describe`/`it`, no bespoke helpers). Behavioral replay via existing `Custom::Scout::PlaygroundRunner` for manual/semi-automated verification (not part of the automated suite).

**Target Platform**: Existing Rails monolith backend (no frontend change; prompt/text-only feature).

**Project Type**: Single Rails application — fork-specific addition confined to the existing `Custom::Scout` namespace under `custom/app/services/custom/scout/`.

**Performance Goals**: N/A — a single regex match per prompt build; negligible cost, no new query.

**Constraints**: Must not modify `app/models/contact.rb` or any other core/upstream file; must not touch `ContactInboxWithContactBuilder` or the placeholder-generation behavior itself; no new account/Scout-level toggle (unconditional behavior, consistent with existing guardrails).

**Scale/Scope**: One new stateless service class (~10 lines), edits to two existing methods in `Custom::Scout::SystemPromptsService` (extract + extend `context_section` with the immediacy/priority-aware warning, add one guardrails bullet carrying the same immediacy/priority language for other channels), one small optional-param addition to `Custom::Scout::PlaygroundRunner` (to make the spec's own replay verification executable — see `research.md`), plus specs. No new section/method is needed for the handoff-suppression requirement (FR-011) — it rides on the existing "no questions in a handoff-ending turn" guardrail. No API surface change, no migration, no UI.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First** — PASS. New logic lives entirely in `custom/app/services/custom/scout/`, a namespace that already exists for this purpose. `Custom::Scout::SystemPromptsService` is itself a fork-owned file (not upstream), so extending it is not a core-file edit. `Contact` (core) is read-only via the already-existing `contact.name` accessor — no new coupling, no `prepend_mod_with` needed since nothing upstream is being overridden.
- **II. Smallest Production-Ready Change** — PASS. One small classifier service (shape-based regex, matching the pattern already prototyped in the source spec), two targeted edits to existing prompt-builder methods, no new abstractions, no speculative configuration/toggle. The 2026-09-02 spec clarifications (handoff suppression, priority over qualification, first-response immediacy, explicit non-website channel scope) added requirements but not new files/classes — the handoff-suppression requirement in particular is satisfied by existing prompt content, so it added a verification step, not new code.
- **III. Adhere to Established Conventions** — PASS. Ruby/RuboCop conventions, compact `class` definition, follows the existing `Custom::Scout::*` service style (stateless class-method services like `Custom::Scout::EmbeddingConfig`, instance-based prompt builder like the existing `SystemPromptsService`).
- **IV. Safe, Reversible Change Management** — PASS. Purely additive text/logic change; fully revertible; no destructive operations.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — PASS (no action needed). Scout is a fork-only (`custom/`) feature with no enterprise overlay counterpart; nothing in `enterprise/` references `SystemPromptsService` or contact naming. Verified via search below (Phase 0).

No violations to justify; Complexity Tracking section left empty.

### Post-Design Re-check (after Phase 1)

Design artifacts (`research.md`, `data-model.md`, `quickstart.md`) confirm the plan holds with no
new risk:

- **I. Upstream Compatibility First** — Still PASS. Design confirmed no core file is touched;
  the only near-miss (adding a `placeholder_name?` method directly on `Contact`) was explicitly
  rejected in `research.md` in favor of the isolated `Custom::Scout::ContactIdentityService`. The
  one additional file identified during design, `playground_runner.rb`, is itself a fork-owned
  file (not upstream), and its change is an optional, backward-compatible keyword param.
- **II. Smallest Production-Ready Change** — Still PASS. Design added exactly one new class, two
  edited methods, and one small optional-param addition (`PlaygroundRunner`) needed to make the
  spec's own stated test plan executable — no speculative scope crept in during design.
- **III–V** — Unchanged from the initial check; no new findings during design affect these.

Gate: **PASS**. Proceed to `/speckit-tasks`.

## Project Structure

### Documentation (this feature)

```text
specs/061-scout-contact-identity/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

No `contracts/` directory: this feature exposes no external interface (no new API endpoint, no new
tool, no new UI). Its only "contract" is an internal Ruby method signature and prompt text, fully
captured in `data-model.md`; a previous Scout-namespace feature in this repo (`060-natural-handoff-message`)
followed the same precedent and omitted `contracts/` for the same reason.

### Source Code (repository root)

Existing single-project Rails monolith. This feature is entirely additive within the existing
fork-specific `custom/` tree — no core (`app/`) or `enterprise/` files are touched.

```text
custom/
├── app/
│   └── services/
│       └── custom/
│           └── scout/
│               ├── contact_identity_service.rb      # NEW — stateless placeholder-name classifier
│               ├── system_prompts_service.rb        # EDIT — extract + extend context_section, add guardrails bullet
│               └── playground_runner.rb              # EDIT — optional contact: param (see research.md)
└── spec/
    └── services/
        └── custom/
            └── scout/
                ├── contact_identity_service_spec.rb  # NEW
                ├── system_prompts_service_spec.rb    # EDIT — add contact-identity examples
                └── playground_runner_spec.rb          # EDIT — cover optional contact: param
```

**Structure Decision**: Single Rails project (already the repo's structure); no frontend, API, or
mobile layer involved. All new/changed files live under the existing `custom/app/services/custom/scout/`
and its mirrored `custom/spec/services/custom/scout/` directory, consistent with how every prior
Scout phase (042–060) has been organized.

## Complexity Tracking

*No entries — Constitution Check reported no violations (see above and post-design re-check below).*
