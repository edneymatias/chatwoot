# Phase 0 Research: Funnel Outcome-Stage Matching for Scout

No items in Technical Context were marked `NEEDS CLARIFICATION` — the two open design questions
identified during spec authoring (multi-stage tie-break, backward-transition scope) were already
resolved in `/speckit-clarify` and are recorded in spec.md's `## Clarifications` section. This
document instead nails down the concrete insertion points and copy decisions Phase 1 design and
`/speckit-tasks` need, since the feature is entirely a text/copy change to existing methods and forms.

## 1. Where the two new `build_funnel_guidelines_lines` bullets go, and how they encode the clarified rules

**Decision**: Append two new bullet strings to the array literal already returned by
`Custom::Scout::SystemPromptsService#build_funnel_guidelines_lines`
(`custom/app/services/custom/scout/system_prompts_service.rb`), after the two existing bullets
(automatic-handoff-on-qualify, disqualification-is-review-not-closure). Bullet 3 (outcome comparison)
must explicitly state the tie-break rule from spec FR-001 (closest/most-specific match wins, no fixed
stage-type precedence) and the forward-only guard from FR-001a (never move an opportunity that already
reached the qualified stage back to an earlier or the disqualified stage) as one instruction, since
both are refinements of the same "compare and move" behavior. Bullet 4 (tool-capability belief) covers
FR-004 verbatim: Scout always has what it needs via `manage_opportunity`/`move_opportunity_stage` to
record qualification data (including dates/times) in the same call that moves the stage, and must
never conclude an external tool is missing.

**Rationale**: `build_funnel_guidelines_lines` already exists specifically to hold this class of
"how to use the funnel context actively" instruction (its two current bullets already cover automatic
handoff and disqualification-is-not-closure); the new bullets are the same genre of instruction, not
a new concern requiring a new method. Keeping the tie-break and forward-only clauses inside the same
bullet as the base comparison instruction (rather than as separate bullets) keeps the three ideas
("compare against descriptions", "closest match wins on ties", "never regress out of qualified")
readable as one coherent behavior instead of three easily-contradicted fragments.

**Alternatives considered**:
- *Separate bullet per clarified rule* (4 bullets total instead of 2) — rejected: spec79.md's original
  proposed diff already ships this as 2 bullets; splitting the tie-break/forward-only clauses into
  their own bullets would double the addition's footprint for no readability gain and risks the model
  treating them as independent, potentially conflicting rules instead of refinements of the same
  instruction.
- *New dedicated method* (e.g. `build_stage_transition_rules_lines`) — rejected per Constitution
  Principle II (Smallest Production-Ready Change): no other guideline in this class currently gets its
  own method, and `funnel_section` already composes `build_funnel_guidelines_lines`'s output inline.

## 2. Where the `guardrails_section` bullet insertion/extension happens

**Decision**: In `#guardrails_section`'s heredoc (same file), insert one new bullet — **"Ritmo e
condução da conversa"** — immediately before the existing **"Respeito ao ritmo do lead"** bullet,
covering spec FR-005/FR-006 (max one question per response; always close with a question/next step
unless the lead just signaled a pause — the exact pause-signal detection/wording already lives in
"Respeito ao ritmo do lead" and is reused, not duplicated). Extend the existing **"Confirmação de
ação"** bullet in place with the FR-007 clause (natural customer-facing language; never expose
internal identifiers, technical field names, or log-style phrasing). Extend the existing
**"Esclarecimento"** bullet in place with the FR-008 clause (open question instead of reciting a
field's allowed-value list as a menu, while still mapping the free-text answer internally).

**Rationale**: Grouping "Ritmo e condução da conversa" directly before "Respeito ao ritmo do lead"
puts all pacing/conversation-flow guidance in one place, per spec79.md's explicit intent ("agrupa
toda diretriz de ritmo/condução num só lugar"). Extending "Confirmação de ação" and "Esclarecimento"
in place (rather than adding new bullets) avoids duplicating the existing bullet's scope and keeps
each topic as a single source of truth the model reads once.

**Alternatives considered**:
- *New standalone bullets for FR-007/FR-008 instead of extending existing ones* — rejected: both
  existing bullets already own the exact behavior being refined (action confirmation; clarifying
  questions for ambiguous/missing data), so a new bullet would either duplicate or contradict the
  existing one over time as one gets edited without the other.

## 3. UI hint copy and exact insertion point

**Decision**: New i18n key `PIPELINE_STAGES_MGMT.FORM.DESC_HINT` in both
`app/javascript/dashboard/i18n/locale/en/opportunities.json` and
`.../pt_BR/opportunities.json`, inserted immediately after the existing `DESC_PLACEHOLDER` key (both
files currently order `NAME_LABEL, NAME_PLACEHOLDER, DESC_LABEL, DESC_PLACEHOLDER, ...`). Copy is
exactly the text spec79.md specifies:
- EN: "This description is also read by the AI to decide when to move a conversation into this stage
  — write it objectively (e.g. 'move here when the lead declines to schedule')."
- PT-BR: "Esta descrição também é usada pela IA para decidir quando mover uma conversa para este
  estágio — escreva de forma objetiva (ex: 'mover aqui quando o lead recusar agendar')."

In both `AddPipelineStage.vue` and `EditPipelineStage.vue`, the hint renders as a `<p>` with
`class="text-xs text-n-slate-11"` placed directly under the existing `DESC_LABEL` `<label>` and above
the description input (`<textarea>` in Add, `<StageDescriptionEditor>` in Edit) — inside the same
`flex flex-col gap-1` wrapper `div`, unconditionally (no `v-if`).

**Rationale**: Matches the exact key-ordering convention both locale files already use (new stage-
description-related keys sit next to `DESC_LABEL`/`DESC_PLACEHOLDER`), and reuses the identical
`text-xs text-n-slate-11` helper-paragraph style `EditPipelineStage.vue` already uses for
`STALE_AFTER_DAYS_HELP` — no new Tailwind classes, no scoped CSS, per project styling rules.
Placing it under the label (not under the input) keeps it visible regardless of textarea/editor
height and matches spec79.md's wording ("logo abaixo do label 'Descrição'").

**Alternatives considered**:
- `@tiptap/extension-placeholder` dynamic placeholder in the rich-text editor — explicitly rejected
  by spec79.md: the extension isn't installed, and a placeholder-when-empty would vanish exactly when
  an operator has already written a non-actionable description, which is the scenario most needing
  the hint.
- Tooltip/popover on hover — rejected: adds interaction complexity and reduces discoverability
  compared to an always-visible paragraph; spec79.md calls for something "sempre visível".

## 4. RuboCop line-length handling for the new/extended bullet strings

**Decision**: Follow the existing backslash-continuation string-literal style already used for the
current multi-line bullets in both methods (e.g. the existing "Confirmação de ação" and "Não execute
`handover_to_human` separadamente..." lines), splitting any new/extended bullet across multiple
`'...' \` string-literal segments so no single source line exceeds 150 characters.

**Rationale**: This is the file's established convention (visible in `guardrails_section` and
`build_funnel_guidelines_lines` already), required by `.rubocop.yml`'s repo-wide 150-char limit with
no `Max`/`Exclude` overrides permitted per project guidelines.

**Alternatives considered**: None — this is a mechanical formatting constraint, not a design choice.

## 5. Verifying prompt-guidance changes actually change model behavior

**Decision**: Automated RSpec coverage (extending
`custom/spec/services/custom/scout/system_prompts_service_spec.rb`) only proves the new/extended text
is present in the built prompt string — it cannot prove the model reliably obeys it. For behavioral
confidence, replay the same three real conversations that motivated this feature
(display_id 19, 18/20, 46 per spec79.md) through `Custom::Scout::PlaygroundRunner.new(scout:,
message:, message_history:).perform`, reconstructing each conversation's message sequence via `rails
runner`, and manually inspect `tool_calls`/`reply` in the result hash for the expected
`move_opportunity_stage` call. This mirrors the runner's existing, already-tested request/response
shape (`{reply:, tool_calls:}` per `playground_runner.rb`) with no code changes needed to run it.

**Rationale**: Matches this codebase's own stated limitation (spec.md Assumptions: "automated tests
can confirm instructions were delivered to the model but not that the model reliably follows them")
and the exact manual verification path spec79.md's Testes section already prescribes, using
infrastructure (`PlaygroundRunner`) that already exists and is already unit-tested — no new tooling
required.

**Alternatives considered**:
- *Skip manual verification, rely solely on RSpec* — rejected: would leave the actual behavioral
  defect (the entire reason for this feature) unverified before considering it done.
- *Build a new automated eval harness for prompt regression testing* — rejected per Constitution
  Principle II: out of scope for a six-bullet prompt-text change; spec.md's Assumptions section
  explicitly scopes this to a manual/scripted smoke test, not new eval infrastructure.
