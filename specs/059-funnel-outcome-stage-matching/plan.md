# Implementation Plan: Funnel Outcome-Stage Matching for Scout

**Branch**: `059-funnel-outcome-stage-matching` | **Date**: 2026-08-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/059-funnel-outcome-stage-matching/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Real conversation transcripts (`spec-preview.md`) show Scout's system prompt already surfaces every
configured pipeline stage description as passive context (`funnel_section`/`format_stage`), but
never instructs the model to actively compare a turn's outcome against those descriptions — so
opportunities silently stay in the wrong stage even when a lead clearly declines (should move to the
disqualification review stage) or confirms with all required data already present (should move to
the qualified stage, triggering its existing automatic handoff). A second gap: the model sometimes
concludes a capability like scheduling is "missing" and hands off to a human instead of recording the
data with tools it already has. Both are pure prompt-guidance additions — two new bullets appended to
`Custom::Scout::SystemPromptsService#build_funnel_guidelines_lines`, encoding the tie-break rule
(closest/most-specific match wins, no fixed precedence between stage types) and the forward-only
guard (never auto-regress an opportunity that already reached the qualified stage) resolved during
`/speckit-clarify`. Four adjacent conversational-quality gaps (stacked questions, inert responses,
internal-identifier leakage, multiple-choice-style enumeration of list values) are resolved by one
new bullet and two extended bullets in `#guardrails_section`. All six are text-only changes to two
existing private methods on one existing class — no new services, no new tool, no schema/migration.
A seventh, independent item adds a static, always-visible i18n hint paragraph under the stage
description field in the two existing pipeline-stage forms, telling operators the description is also
read by the AI — purely informational UI copy, no new validation or save-path behavior.

## Technical Context

**Language/Version**: Ruby 3.4.4 (backend prompt text, per `Gemfile`/`.ruby-version`); Vue 3
`<script setup>` (frontend hint, per existing `AddPipelineStage.vue`/`EditPipelineStage.vue`)

**Primary Dependencies**: None new. Backend: plain string/heredoc methods already on
`Custom::Scout::SystemPromptsService` (no `ruby_llm`/schema involvement — this service only builds
the prompt text consumed by `Custom::Scout::AgentRunner#llm_chat`, unchanged here). Frontend: existing
`vue-i18n` `$t()`/`t()` calls already used by both pipeline-stage form components.

**Storage**: N/A. No new columns/tables — `ichatr_pipeline_stages.description` (existing column) is
the only data this feature reads, and it already flows into the prompt via `format_stage`.

**Testing**: RSpec for the two prompt-text methods, per repo convention
(`custom/spec/services/custom/scout/system_prompts_service_spec.rb`), run via `docker compose exec
rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/system_prompts_service_spec.rb`.
No new frontend unit test is planned for the static hint paragraph (no conditional logic to cover);
manual verification only, per `quickstart.md`.

**Target Platform**: Rails app server + Vue dashboard SPA (this fork's existing Docker/Podman stack)

**Project Type**: Web application (Rails monolith backend + Vue frontend) — backend prompt-text
change with no new endpoint; frontend change is two existing Options settings modals gaining one
static paragraph each, no new route/component.

**Performance Goals**: N/A — no new LLM call, no new request path; the prompt grows by roughly seven
short bullet lines total (two in `funnel_section`, one new + two extended in `guardrails_section`),
negligible relative to the existing prompt's stage/attribute listing which already scales with
account configuration.

**Constraints**: RuboCop's 150-character line-length limit applies to every new/edited Ruby string
line (per `.rubocop.yml`, no `Max`/`Exclude` overrides allowed) — the heredoc/string-concatenation
style already used in `guardrails_section`/`build_funnel_guidelines_lines` (backslash-continued
string literals) must be preserved for any bullet that would otherwise exceed it. No hardcoded
keyword/phrase business rule may be introduced (spec FR-011) — every new bullet must stay a general
instruction to compare against operator-authored stage descriptions, never a specific trigger phrase
or stage name. The UI hint must render unconditionally (not tied to `v-if="!description"` or any
placeholder mechanic) per spec FR-009 — spec79.md explicitly rejects a `@tiptap/extension-placeholder`
dynamic-placeholder approach because it disappears exactly when an operator has already written a
non-actionable description, which is the case most needing the hint.

**Scale/Scope**: Single-tenant self-hosted install. Modified files only: 1 Ruby service (2 private
methods edited), 2 Vue components (1 hint paragraph each), 2 backend-irrelevant i18n JSON files (1 new
key each, en + pt_BR). No new files except the existing spec file gaining new `it` blocks.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First** — PASS. Every file touched
  (`custom/app/services/custom/scout/system_prompts_service.rb`,
  `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/{Add,Edit}PipelineStage.vue`,
  the two `opportunities.json` locale files) is fork-owned code with no upstream Chatwoot equivalent
  (Scout and the Kanban/Opportunities pipeline-stage UI are both fork-specific features layered on
  top of upstream). No core/upstream file is edited, renamed, or restructured.
- **II. Smallest Production-Ready Change** — PASS. No new abstraction, service, column, or feature
  flag is introduced for what is entirely additive prompt copy plus one static UI string; the two
  clarified rules (tie-break, forward-only) are folded into the same existing bullet list rather than
  spawning new methods or a rules engine.
- **III. Adhere to Established Conventions** — PASS. New Ruby string literals follow the existing
  compact-heredoc/backslash-continuation style already in `guardrails_section` and
  `build_funnel_guidelines_lines`, subject to the same 150-char RuboCop limit; new specs extend the
  existing `RSpec.describe Custom::Scout::SystemPromptsService` file using `let!`/direct per-example
  setup already established there (no new helper methods). Frontend hint follows the existing
  `text-xs text-n-slate-11` Tailwind-only paragraph convention already used elsewhere in these forms
  (e.g. the `STALE_AFTER_DAYS_HELP` paragraph in `EditPipelineStage.vue`) — no scoped CSS, no inline
  styles.
- **IV. Safe, Reversible Change Management** — PASS. Purely additive text; no migration, no
  destructive operation, no behavior gated by a flag that could strand existing accounts (accounts
  with no stage descriptions configured see zero behavior change, per spec FR-010 — the new bullets
  only ever activate when there is a description to match against).
- **V. Dual-Tree Awareness (OSS + Enterprise)** — N/A/PASS. `Custom::Scout::SystemPromptsService` and
  the pipeline-stage settings UI have no `enterprise/` counterpart (Captain's own
  `enterprise/app/services/captain/llm/system_prompts_service.rb` is a separate, unrelated class for a
  different product surface); nothing in `enterprise/` needs a mirrored change.

No violations. Complexity Tracking is not needed.

**Post-Phase 1 re-check**: `data-model.md` confirms no schema or persisted-entity change — every
"entity" in the spec (Pipeline Stage Description, Conversation Turn Outcome, Opportunity Stage
Transition, Qualification Data) maps to an existing Ruby/DB concept already in place before this
feature; `research.md` confirms the exact insertion points for both clarified rules inside
`build_funnel_guidelines_lines` and the exact `DESC_LABEL`-adjacent insertion point for the UI hint in
both forms and both locale files; `quickstart.md` introduces no new endpoint or contract. All five
gates above still PASS unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/059-funnel-outcome-stage-matching/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

No `contracts/` directory: this feature adds no new endpoint, public API, or frontend data contract —
it only changes prompt text an existing LLM call already consumes, plus one static, non-interactive
UI paragraph with no new props/events.

### Source Code (repository root)

```text
custom/app/services/custom/scout/
└── system_prompts_service.rb       # MODIFIED: #build_funnel_guidelines_lines gains two bullets
                                     #   (outcome-vs-description comparison with the closest-match
                                     #   tie-break rule and the forward-only guard; existing-tools-
                                     #   are-sufficient guidance for qualification data incl. dates);
                                     #   #guardrails_section gains one new bullet ("Ritmo e condução
                                     #   da conversa" — one question per turn, always close with a
                                     #   next step unless the lead signaled a pause) inserted before
                                     #   "Respeito ao ritmo do lead", and extends the existing
                                     #   "Confirmação de ação" bullet (natural language, no internal
                                     #   identifiers/field names/log phrasing) and "Esclarecimento"
                                     #   bullet (open question instead of reciting allowed-value
                                     #   lists)

custom/spec/services/custom/scout/
└── system_prompts_service_spec.rb  # EXTENDED: new `it` blocks under the existing
                                     #   `funnel_section (User Story 1)` describe block (outcome-
                                     #   comparison bullet present; existing-tools-sufficient bullet
                                     #   present) and under the top-level `.build` describe block
                                     #   (extended "Confirmação de ação" assertions; new
                                     #   "Esclarecimento" open-question assertions; new "Ritmo e
                                     #   condução da conversa" bullet assertions)

app/javascript/dashboard/routes/dashboard/settings/pipelineStages/
├── AddPipelineStage.vue            # MODIFIED: static hint paragraph
                                     #   (text-xs text-n-slate-11) added directly below the
                                     #   PIPELINE_STAGES_MGMT.FORM.DESC_LABEL label, above the
                                     #   textarea; always rendered (no v-if)
└── EditPipelineStage.vue           # MODIFIED: same hint paragraph added directly below the same
                                     #   label, above <StageDescriptionEditor>; always rendered

app/javascript/dashboard/i18n/locale/
├── en/opportunities.json           # MODIFIED: new key PIPELINE_STAGES_MGMT.FORM.DESC_HINT,
                                     #   inserted immediately after DESC_PLACEHOLDER
└── pt_BR/opportunities.json        # MODIFIED: same key, Portuguese copy, same position
```

**Structure Decision**: Existing web-application layout (Rails backend + Vue frontend) is unchanged.
All six prompt-guidance items live in the two already-identified private methods of the one existing
service class (`custom/app/services/custom/scout/system_prompts_service.rb`) rather than new
files/classes, since they are all just additional bullets in an already-established
guideline-list-building pattern (`build_funnel_guidelines_lines` returning an `Array` of strings,
`guardrails_section` returning a `<<~SECTION.strip` heredoc). The UI hint reuses the two forms'
existing static-helper-text convention (plain `<span>`/paragraph under a label, e.g.
`STALE_AFTER_DAYS_HELP`) rather than introducing a tooltip/popover component or the rich-text
placeholder extension spec79.md explicitly rules out.

## Complexity Tracking

> Not applicable — Constitution Check reported no violations.
