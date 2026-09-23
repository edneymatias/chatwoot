# Implementation Plan: Response Auditor Handoff Message Quality

**Branch**: `078-handoff-message-quality` | **Date**: 2026-09-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/078-handoff-message-quality/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command; its definition describes the execution workflow.

## Summary

`Custom::Scout::ActionClassifierService`'s `out_of_scope_commercial_request` criterion is the only
one of the four handoff reasons with no textual-evidence anchor, so a single declined qualification
question (e.g. "ainda não quero agendar") after otherwise-demonstrated commercial intent gets
misread as out-of-scope and triggers a real, irreversible handoff (confirmed by production replay,
conversation 71393/display 45007). Once a classifier-driven handoff does legitimately fire, its two
downstream renderings are also poor: `Custom::Scout::HandoffService#create_transfer_note` interpolates
the raw English enum (`out_of_scope_commercial_request`) straight into the internal note, and
`Custom::Scout::ResponseAuditor#execute_handoff` never passes `message:`, so the customer always sees
the single generic `conversations.scout.handoff` string regardless of reason.

The fix has two independent parts: (1) tighten the `out_of_scope_commercial_request` prompt criterion
with an anti-hallucination anchor and an explicit single-decline carve-out, mirroring the anchor
pattern already used for `human_offer_accepted`; (2) add a deterministic reason→{note, message} lookup
(new `conversations.scout.handoff_reasons.<reason>.{note,message}` i18n namespace, pt-BR and en) applied
in the classifier-driven handoff path only, resolving the note label by `account.locale` and the
customer message by `conversation.language` (mirroring how `HandoffService#conversation_locale` already
resolves the existing generic fallback), with graceful fallback to today's generic text for a missing
or unrecognized reason. No additional LLM call is introduced.

## Technical Context

**Language/Version**: Ruby 3.4.4, Rails 7.2.3.1 (existing app, no version change)

**Primary Dependencies**: `ruby_llm-schema` (existing `ActionClassifierSchema`), Rails `I18n`
(existing `config/locales/{en,pt_BR}.yml`), `Messages::MessageBuilder` (existing message creation)

**Storage**: N/A — no schema/migration change; reason labels and messages are static i18n data, not
persisted rows

**Testing**: RSpec (`custom/spec/services/custom/scout/`), container-run via
`docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec <file>`

**Target Platform**: Existing Rails backend service (no new platform surface)

**Project Type**: Web application backend — fork-specific isolated module under `custom/app/services/custom/scout/`

**Performance Goals**: N/A — deterministic hash/i18n lookup only, no measurable latency change;
explicitly must add zero additional LLM calls (FR-011)

**Constraints**: Must not alter the existing double-confirmation requirement
(`ResponseAuditor#handoff_confirmed?`, FR-003); must not change the other two handoff paths
(`handover_to_human` tool call, qualified-stage handoff, FR-012); en/pt_BR key parity (FR-010)

**Scale/Scope**: 4 fixed reason codes × 2 fields (note, message) × 2 locales = 16 new static strings;
one classifier prompt criterion revised; two call sites touched
(`HandoffService#create_transfer_note`/`#perform`, `ResponseAuditor#execute_handoff`)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. `Custom::Scout::*` is an already-isolated fork tree
  (mirrors `enterprise/` convention); this feature only edits files already inside that tree plus the
  two shared-but-fork-owned locale files (`config/locales/{en,pt_BR}.yml`), adding new leaf keys under
  a new `conversations.scout.handoff_reasons` namespace — no restructuring of upstream files, no new
  extension point needed since nothing here touches core/enterprise entry points.
- **II. Smallest Production-Ready Change**: PASS. Reuses the existing `reason` string already threaded
  through `HandoffService#perform`/`#create_transfer_note` and `ResponseAuditor#execute_handoff`; no
  new abstraction beyond a lookup table, no speculative reason values beyond the four that already
  exist in `ActionClassifierSchema::REASONS`.
- **III. Adhere to Established Conventions**: PASS. New strings follow the existing
  `config/locales/{en,pt_BR}.yml` nesting/key-parity convention (`conversations.scout.*`); no new
  Vue/JS surface.
- **IV. Safe, Reversible Change Management**: PASS. No destructive operations; a prompt-text and
  i18n-data change is fully reversible by editing the same files back.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS, no action needed. `enterprise/` has an
  unrelated `Captain::Llm::AssistantActionClassifierService`/`assistant_action_classifier` (upstream's
  own Captain feature, different class hierarchy, different locale keys) — confirmed by search; no
  enterprise file exists for `Custom::Scout::*`, and this feature does not touch Captain, so no
  override/extension-point decision is needed here.
- **VI–IX (TDD, Observable Behavior, Functional Slice, Surgical Test Scope)**: PASS, to be honored in
  the implementation phase — new/changed specs will exercise real `Custom::Scout::HandoffService`/
  `ActionClassifierService` behavior (persisted `Message` content, not mocked internals) via the
  existing `custom/spec/services/custom/scout/{handoff_service,action_classifier_service}_spec.rb`
  files, run surgically per file, not as part of this planning phase.

No violations. Complexity Tracking section not needed.

**Post-Design Re-check (after Phase 1)**: Confirmed still PASS on all points above — Phase 1 design
(`data-model.md`, `contracts/handoff-reason-mapping.md`, `quickstart.md`) did not introduce any new
class, table, endpoint, or extension point beyond what Phase 0 already anticipated (one private
lookup method inside the existing `Custom::Scout::HandoffService`, 16 new static i18n leaf strings in
the two already fork-owned locale files, one revised prompt paragraph in
`Custom::Scout::ActionClassifierService`). No new Complexity Tracking entries required.

## Project Structure

### Documentation (this feature)

```text
specs/078-handoff-message-quality/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md         # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   └── handoff-reason-mapping.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
custom/app/services/custom/scout/
├── action_classifier_service.rb    # system_instructions: revise out_of_scope_commercial_request
│                                    #   criterion (anchor + single-decline carve-out)
├── handoff_service.rb              # create_transfer_note: resolve reason label via lookup +
│                                    #   account.locale; perform/send_public_handoff_message: resolve
│                                    #   reason-specific message via lookup + conversation_locale
└── response_auditor.rb             # execute_handoff: no change to call signature (reason already
                                     #   passed through); lookup resolution happens inside HandoffService

config/locales/
├── en.yml                          # new conversations.scout.handoff_reasons.<reason>.{note,message}
└── pt_BR.yml                       # same keys, pt-BR content, kept in sync (FR-010)

custom/spec/services/custom/scout/
├── action_classifier_service_spec.rb   # new: revised criterion does not fire on single decline
│                                        #   with prior commercial intent; still fires on genuine
│                                        #   out-of-scope cases (no regression)
└── handoff_service_spec.rb             # new: per-reason note label (account.locale) + per-reason
                                         #   message (conversation_locale), both locales; fallback to
                                         #   generic text for unknown/nil reason
```

**Structure Decision**: No new top-level directories. All production changes stay inside the
existing `custom/app/services/custom/scout/` tree (Constitution Principle I) plus the two
already-fork-owned locale files; all test changes stay inside the existing
`custom/spec/services/custom/scout/` tree. No `contracts/` code changes — `contracts/` here documents
the reason→{note,message} lookup as a data contract between the classifier's fixed `REASONS` enum and
the two locale files, since `en.yml`/`pt_BR.yml` key parity (FR-010) is the closest thing this feature
has to an external interface.

## Complexity Tracking

*No violations — section not applicable.*
